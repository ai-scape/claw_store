# AI Intelligence System — Global Config

# === IDENTITY ===
$script:AI_USER = "Ayush"
$script:AI_USER_ID = "7739622002"
$script:AI_TZ = "Asia/Kolkata"  # IST

# === TELEGRAM ===
# Bot token from @BotFather and your personal chat ID
$script:TG_BOT_TOKEN = "8664233886:AAFG_Rz8jrP49udZkj_U4VU-JCZUTM4vJg0"
$script:TG_CHAT_ID   = "7739622002"  # Your Telegram ID (Ayush)

# === THEAISEARCH WEEKLY VIDEO ===
$script:CHANNEL_URL = "https://www.youtube.com/@theAIsearch/videos"
$script:CHANNEL_ID = "UCz5BO7lFH_7ngIk6CMcpzHA"
$script:VIDEO_SCHEDULE_DAY = "Sunday"
$script:VIDEO_SCHEDULE_TIME = "18:00"  # IST

# === DAILY COMPANY MONITORING (Media & Entertainment AI) ===
# Rotating schedule — each company checked at least once per week
$script:DAILY_COMPANIES = @{
    "Monday"    = @("Nvidia", "OpenAI", "Google DeepMind")
    "Tuesday"   = @("Runway", "Luma AI", "Sora")
    "Wednesday" = @("Kling", "Minimax Hailuo", "Vidu")
    "Thursday"  = @("Alibaba Qwen", "Alibaba Wan", "ByteDance Seed")
    "Friday"    = @("Z AI", "Moonshot AI", "Mistral")
    "Saturday"  = @("Higgsfield", "Freepik", "OpenArt", "InVideo")
    "Sunday"    = @("ArXiv CS.AI", "ArXiv CS.CV", "HuggingFace Papers")
}

# === RESEARCH PAPER SITES ===
$script:ARXIV_RSS = @(
    "https://rss.arxiv.org/rss/cs.AI",
    "https://rss.arxiv.org/rss/cs.CV",
    "https://rss.arxiv.org/rss/cs.CL",
    "https://rss.arxiv.org/rss/cs.LG"
)
$script:PAPER_TRACKED_KEYWORDS = @(
    "video generation", "image generation", "motion", "character animation",
    "world model", "multimodal", "LLM", "reasoning", "agent",
    "diffusion", "transformer", "generative AI", "autoregressive"
)

# === AI FILMMAKER REDDIT SUBREDDITS ===
$script:REDDIT_SUBREDDITS = @(
    "r/sora", "r/StableDiffusion", "r/OpenAI", "r/LocalLLaMA",
    "r/SoraArt", "r/AI_Video", "r/Replicate", "r/AIArt"
)
$script:X_HANDLES = @(
    "@runwayml", "@LumaLabsAI", "@OpenAI", "@sabor独秀",
    "@kairos_ch", "@ptrnspr", "@剪映", "@MinimaxIO"
)

# === DATABASE PATHS ===
$script:DB_BASE = "$PSScriptRoot/../database"
$script:DB_COMPANIES = "$DB_BASE/companies"
$script:DB_PAPERS = "$DB_BASE/papers"
$script:DB_FILMMAKERS = "$DB_BASE/filmmakers"
$script:DB_AGGREGATORS = "$DB_BASE/aggregators"
$script:DB_VIDEOS = "$DB_BASE/videos"
$script:DB_REPORTS = "$DB_BASE/reports"

# === LOGGING ===
$script:LOG_DIR = "$PSScriptRoot/../logs"
$script:LOG_LEVEL = "INFO"  # DEBUG, INFO, WARN, ERROR
