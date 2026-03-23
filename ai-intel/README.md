# AI Intelligence System — README

> Your personal AI monitoring system for Ayush (ID: 7739622002)

## What it does

- **📺 theAISearch Weekly Video** — Every Sunday 18:00 IST, fetches the latest video metadata, description, links, and timestamps. Sends a Telegram summary.
- **🏢 Company Monitoring (Daily)** — Rotating schedule across 16 AI companies in media & entertainment.
- **📚 Research Papers (Mon/Wed/Fri/Sat)** — ArXiv RSS for cs.AI, cs.CV, cs.CL, cs.LG, auto-categorized by topic.
- **🎨 AI Filmmakers (Tue/Thu)** — Reddit hot posts + X/Twitter via Nitter, prompt extraction.
- **🌐 AI Aggregators (Sat)** — Higgsfield, Freepik, OpenArt, InVideo updates.
- **📊 Weekly Report (Sunday)** — Consolidated digest sent to Telegram.

## Schedule

| Day | Task |
|-----|------|
| Monday | Nvidia, OpenAI, Google DeepMind + ArXiv papers |
| Tuesday | Runway, Luma AI, Sora + Filmmakers Reddit/X |
| Wednesday | Kling, Minimax Hailuo, Vidu + ArXiv papers |
| Thursday | Alibaba Qwen, Wan, ByteDance Seed + Filmmakers |
| Friday | Z AI, Moonshot AI, Mistral + ArXiv papers |
| Saturday | Aggregators + ArXiv papers |
| Sunday | theAISearch video + Weekly Report |

## Setup

### 1. Prerequisites

```powershell
# Install Node.js (for Playwright)
winget install OpenJS.NodeJS

# Install Playwright
npm install -g playwright
npx playwright install chromium

# PowerShell 7+ (optional but recommended)
winget install Microsoft.PowerShell
```

### 2. Telegram Bot Token

Create a file at:
```
workspace/.secrets/telegram_bot_token.txt
```
Paste your Telegram bot token (from @BotFather) into this file.

### 3. Run the dispatcher

```powershell
# Full auto run (picks up today's schedule)
pwsh -File scripts/dispatcher.ps1

# Run specific module
pwsh -File scripts/dispatcher.ps1 -RunMode companies
pwsh -File scripts/dispatcher.ps1 -RunMode papers
pwsh -File scripts/dispatcher.ps1 -RunMode filmmakers
pwsh -File scripts/dispatcher.ps1 -RunMode video
pwsh -File scripts/dispatcher.ps1 -RunMode report -SendReport

# Test on a specific day
pwsh -File scripts/dispatcher.ps1 -RunMode auto -DayOverride Sunday
```

## Database Structure

```
database/
├── companies/
│   ├── nvidia/
│   ├── openai/
│   ├── google-deepmind/
│   ├── runway/
│   ├── luma-ai/
│   ├── kling/
│   ├── minimax-hailuo/
│   ├── vidu/
│   ├── alibaba-qwen/
│   ├── alibaba-wan/
│   ├── bytedance-seed/
│   ├── z-ai/
│   ├── moonshot-ai/
│   ├── mistral/
│   ├── higgsfield/
│   ├── freepik/
│   ├── openart/
│   └── invideo/
├── papers/
│   ├── Video-Generation/
│   ├── Image-Generation/
│   ├── World-Models/
│   ├── Multimodal/
│   ├── AI-Agent/
│   └── ...
├── filmmakers/
│   └── (reddit posts + prompts + tweets)
├── aggregators/
│   └── (aggregator updates)
├── videos/
│   └── (theAISearch video metadata)
└── reports/
    ├── weekly_2026-03-29.md
    └── daily_2026-03-24.md
```

## Cron Jobs (Gateway)

```powershell
# Sunday 18:00 IST — Weekly report
# Daily 09:00 IST — Daily companies + papers
# Tuesday/Thursday 10:00 IST — Filmmakers
```

## Modules

| Script | What it does |
|--------|--------------|
| `config.ps1` | All configuration (paths, schedule, API keys) |
| `dispatcher.ps1` | Master routing based on day/time |
| `monitor_companies.ps1` | Per-company RSS/blog/GitHub monitoring |
| `monitor_papers.ps1` | ArXiv RSS parsing + auto-categorization |
| `monitor_filmmakers.ps1` | Reddit API + Nitter RSS + prompt extraction |
| `monitor_aggregators.ps1` | AI platform aggregator monitoring |
| `monitor_video.ps1` | Playwright-based YouTube video + description fetch |
| `report_weekly.ps1` | Consolidated report builder (daily/weekly) |
| `send_telegram.ps1` | Telegram bot message sender |
| `query_kb.ps1` | Query the knowledge base |

## Querying the Knowledge Base

```powershell
# Search all databases
pwsh -File scripts/query_kb.ps1 -Query "video generation"

# Search specific category
pwsh -File scripts/query_kb.ps1 -Query "Sora" -Category companies

# Generate a custom report
pwsh -File scripts/query_kb.ps1 -Query "Nvidia GTC" -Report
```

## Troubleshooting

**Playwright fails with "nitter" or "403":** Nitter instances are often rate-limited. Check the instance list in `monitor_filmmakers.ps1`.

**Reddit API returns 429:** Too many requests. Wait and retry. The script includes 500ms delays between calls.

**ArXiv RSS times out:** Try a different ArXiv mirror or use a VPN.

**Telegram not sending:** Check `.secrets/telegram_bot_token.txt` exists and the bot has started a chat with your user ID.
