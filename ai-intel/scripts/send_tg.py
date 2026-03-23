"""
send_tg.py — Send theAISearch YouTube video description to Telegram.
Reads from temp_video.description (populated by monitor_video.ps1), extracts
video metadata from temp_video.info.json, and sends the content via Telegram bot.

Usage:
    python send_tg.py              # normal: read from files
    python send_tg.py --browser    # fetch fresh via OpenClaw browser first
    python send_tg.py --test       # print message to stdout without sending
"""
import os
import sys
import json
import re
import time
import subprocess
import argparse
from pathlib import Path

# ── project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT    = Path(__file__).resolve().parent.parent.parent
DESCRIPTION_FILE = PROJECT_ROOT / "temp_video.description"
INFO_FILE       = PROJECT_ROOT / "temp_video.info.json"
MAX_MSG_SIZE    = 3500   # safety margin under Telegram's 4096 limit


# ── Telegram helpers ───────────────────────────────────────────────────────────
def load_telegram_config():
    """Load bot token and chat ID from config.ps1 via PowerShell."""
    config_path = Path(__file__).resolve().parent / "config.ps1"
    try:
        result = subprocess.run(
            ["powershell", "-Command",
             f". '{config_path}'; Write-Output \"TG_BOT_TOKEN=${{TG_BOT_TOKEN}}\"; "
             f"Write-Output \"TG_CHAT_ID=${{TG_CHAT_ID}}\""],
            capture_output=True, text=True, timeout=30
        )
        config = {}
        for line in result.stdout.splitlines():
            if "=" in line:
                key, _, value = line.partition("=")
                config[key.strip()] = value.strip()
        return config.get("TG_BOT_TOKEN", ""), config.get("TG_CHAT_ID", "")
    except Exception as e:
        print(f"[WARN] Could not load config: {e}", file=sys.stderr)
        return "", ""


def send_message(bot_token: str, chat_id: str, text: str) -> bool:
    """Send a single message via Telegram Bot API using curl (most reliable on Windows)."""
    import urllib.parse, subprocess

    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML"
    })
    cmd = [
        "curl", "-s", "-X", "POST", url,
        "-H", "Content-Type: application/x-www-form-urlencoded",
        "-d", data
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0 and result.stdout.strip():
            resp = json.loads(result.stdout)
            if resp.get("ok"):
                print(f"  [OK] Message {resp['result']['message_id']} sent")
                return True
            print(f"  [ERROR] Telegram error: {resp.get('description', resp)}", file=sys.stderr)
            return False
        print(f"  [ERROR] curl failed (code={result.returncode}): {result.stderr[:200]}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  [ERROR] Request failed: {e}", file=sys.stderr)
        return False


def send_document(bot_token: str, chat_id: str, file_path: str,
                  caption: str = "", mime_type: str = "application/pdf") -> bool:
    """Send a file as a Telegram document (PDF, etc.) using curl with multipart/form-data."""
    import subprocess

    if not os.path.exists(file_path):
        print(f"  [ERROR] File not found: {file_path}", file=sys.stderr)
        return False

    url = f"https://api.telegram.org/bot{bot_token}/sendDocument"

    # Build curl command with -F for multipart/form-data
    cmd = [
        "curl", "-s", "-X", "POST", url,
        "-F", f"chat_id={chat_id}",
        "-F", f"document=@{file_path}",
        "-F", f"caption={caption}",
        "-F", 'parse_mode=HTML'
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode == 0 and result.stdout.strip():
            resp = json.loads(result.stdout)
            if resp.get("ok"):
                msg_id = resp["result"].get("message_id", "?")
                print(f"  [OK] Document sent (message_id={msg_id})")
                return True
            err = resp.get("description", resp)
            print(f"  [ERROR] Telegram error: {err}", file=sys.stderr)
            return False
        # Non-json response (might be an error in curl)
        err = result.stdout.strip() or result.stderr.strip()
        print(f"  [ERROR] curl failed (code={result.returncode}): {err[:300]}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  [ERROR] Request failed: {e}", file=sys.stderr)
        return False


def split_messages(text: str, chunk_size: int = MAX_MSG_SIZE) -> list[str]:
    """Split long text into chunks that fit Telegram's limit."""
    chunks = []
    while len(text) > chunk_size:
        split_at = text.rfind("\n\n", 0, chunk_size)
        if split_at < chunk_size * 0.3:
            split_at = text.rfind("\n", 0, chunk_size)
        if split_at < chunk_size * 0.3:
            split_at = chunk_size
        chunks.append(text[:split_at].strip())
        text = text[split_at:].strip()
    if text:
        chunks.append(text)
    return chunks


# ── Video info from files ──────────────────────────────────────────────────────
def load_video_info() -> dict:
    """Load video metadata from temp_video.info.json."""
    try:
        with open(INFO_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[WARN] Could not load {INFO_FILE}: {e}", file=sys.stderr)
        return {}


def get_description_from_file() -> str:
    """Read video description from temp_video.description."""
    try:
        with open(DESCRIPTION_FILE, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""
    except Exception as e:
        print(f"[WARN] Could not read {DESCRIPTION_FILE}: {e}", file=sys.stderr)
        return ""


def save_description(text: str):
    """Save description text to temp_video.description."""
    try:
        with open(DESCRIPTION_FILE, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  [OK] Saved description ({len(text)} chars) to {DESCRIPTION_FILE}")
    except Exception as e:
        print(f"[WARN] Could not save: {e}", file=sys.stderr)


# ── OpenClaw browser: fetch fresh video description ───────────────────────────
def get_video_info_via_browser() -> dict:
    """
    Use OpenClaw browser to open theAISearch channel, navigate to the latest
    video, expand the description, and return {title, date, description}.
    """
    browser = ["openclaw", "browser", "--browser-profile", "openclaw"]

    def run(args, timeout=60):
        try:
            r = subprocess.run(browser + args, capture_output=True, text=True, timeout=timeout)
            return r.stdout, r.stderr
        except Exception as e:
            return "", f"[error: {e}]"

    # 1. Start browser
    print("  [browser] Starting...")
    run(["start"])
    time.sleep(3)

    # 2. Open channel videos page
    print("  [browser] Opening @theAIsearch/videos ...")
    run(["open", "https://www.youtube.com/@theAIsearch/videos"])
    time.sleep(6)

    # 3. Find latest video link in the video grid
    print("  [browser] Finding latest video...")
    out, _ = run(["snapshot"])
    lines = out.strip().split("\n")

    video_url = None
    for line in lines:
        m = re.search(r'/url:\s*(/watch\?v=[a-zA-Z0-9_-]{11})', line)
        if m:
            video_url = m.group(1)
            break

    if not video_url:
        print("  [browser] Could not find video link — using featured video fallback")
        video_url = "/watch?v=HCVkBC1Vhcw"

    full_url = f"https://www.youtube.com{video_url}"
    print(f"  [browser] Navigating to: {full_url}")
    run(["open", full_url])
    time.sleep(5)

    # 4. Expand description ("...more" button)
    out2, _ = run(["snapshot"])
    more_ref = None
    for line in out2.strip().split("\n"):
        if "...more" in line.lower() and "ref=" in line:
            m = re.search(r'\[ref=([^\]]+)\]', line)
            if m:
                more_ref = m.group(1)
                break

    if more_ref:
        print(f"  [browser] Expanding description (ref={more_ref})...")
        run(["click", more_ref])
        time.sleep(2)
    else:
        print("  [browser] No '...more' button found, description may already be expanded")

    # 5. Final snapshot with full description
    out3, _ = run(["snapshot"])

    # Parse title (h1)
    title = "theAISearch — Latest Video"
    for line in out3.strip().split("\n"):
        m = re.search(r'heading\s+"([^"]+)"\s+\[level=1\]', line)
        if m:
            title = m.group(1)
            break

    # Parse upload date
    date = ""
    for line in out3.strip().split("\n"):
        m = re.search(r'([A-Za-z]+ \d+, \d{4})', line)
        if m and not date:
            date = m.group(1)
            break

    # Parse description: text: "..." and link "..." entries
    desc_parts = []
    for line in out3.strip().split("\n"):
        for t in re.findall(r'text:\s*"([^"]*)"', line):
            t = t.strip()
            if t and len(t) > 4:
                desc_parts.append(t)
        for link in re.findall(r'link\s+"([^"]+)"\s+\[ref=', line):
            link = link.strip()
            if link and len(link) > 4 and "youtube.com" not in link:
                desc_parts.append(link)

    description = "\n".join(desc_parts)

    print(f"  [browser] Title : {title}")
    print(f"  [browser] Date  : {date}")
    print(f"  [browser] Description: {len(description)} chars")

    return {"title": title, "date": date, "description": description}


# ── Formatting ─────────────────────────────────────────────────────────────────
def format_telegram_message(info: dict) -> str:
    """Build the Telegram HTML message from video info dict."""
    title = info.get("title", "theAISearch — Latest Video")
    date  = info.get("date", "")
    desc  = info.get("description", "")

    header = f"* {title} *"
    if date:
        header += f"\nDate: {date}"

    header += "\n\nVideo Description:\n"
    header += "-" * 20 + "\n"

    # Truncate description to fit in one message with the header
    # Account for header length and some buffer
    available = MAX_MSG_SIZE - len(header) - 200
    if len(desc) > available and available > 0:
        # Try to cut at a clean line boundary
        truncated = desc[:available]
        cut = truncated.rfind("\n")
        if cut > available * 0.7:
            truncated = truncated[:cut]
        else:
            truncated = truncated[:available]
        suffix = f"\n... ({len(desc) - len(truncated)} chars truncated)"
        if len(truncated) + len(suffix) <= MAX_MSG_SIZE - len(header):
            desc = truncated + suffix
        else:
            desc = truncated + "\n... (truncated)"
    elif not desc:
        desc = "(No description available.)"

    return header + desc


# ── Main ───────────────────────────────────────────────────────────────────────
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def main():
    parser = argparse.ArgumentParser(description="Send theAISearch video to Telegram")
    parser.add_argument("--browser", action="store_true",
                        help="Fetch fresh description via OpenClaw browser")
    parser.add_argument("--test", action="store_true",
                        help="Print message to stdout without sending")
    parser.add_argument("--file", metavar="PATH", type=str,
                        help="Send a local file (PDF, etc.) as a Telegram document")
    args = parser.parse_args()

    # 1. Bot config
    bot_token, chat_id = load_telegram_config()
    if not bot_token or not chat_id:
        print("ERROR: Missing TG_BOT_TOKEN or TG_CHAT_ID", file=sys.stderr)
        sys.exit(1)
    print(f"[OK] Bot configured (chat_id={chat_id})")

    # 2. Send a file if --file is given
    if args.file:
        file_path = os.path.expanduser(args.file)
        print(f"\nSending file: {file_path}")
        ok = send_document(bot_token, chat_id, file_path)
        if not ok:
            sys.exit(1)
        print("[OK] File sent to Telegram.")
        return

    # 3. Gather video info
    if args.browser:
        print("Fetching video info via OpenClaw browser...")
        info = get_video_info_via_browser()
        if info.get("description"):
            save_description(info["description"])
    else:
        # Read from files (set by monitor_video.ps1)
        info = load_video_info()
        desc = get_description_from_file()
        if desc:
            info["description"] = desc
        else:
            print("temp_video.description is empty — run with --browser to fetch fresh")
            # Fall back: try browser
            print("Falling back to browser fetch...")
            info2 = get_video_info_via_browser()
            if info2.get("description"):
                info = info2
                save_description(info2["description"])

    if not info.get("description"):
        print("✗ No description found.", file=sys.stderr)
        sys.exit(1)

    # 3. Format message
    message = format_telegram_message(info)
    print(f"\nMessage preview ({len(message)} chars):")
    print("─" * 40)
    print(message[:500])
    print("…")
    print("─" * 40)

    # 4. Send or test
    if args.test:
        print("\n[Test mode] Skipping send.")
        return

    print("\nSending to Telegram...")
    chunks = split_messages(message)
    print(f"Split into {len(chunks)} message(s)")
    for i, chunk in enumerate(chunks):
        if len(chunks) > 1:
            chunk += f"\n\n<part {i+1}/{len(chunks)}>"
        ok = send_message(bot_token, chat_id, chunk)
        if not ok:
            print("ERROR: Send failed, stopping.")
            sys.exit(1)
        if i < len(chunks) - 1:
            time.sleep(1)

    print("\n[OK] Done -- message sent to Telegram.")


if __name__ == "__main__":
    main()
