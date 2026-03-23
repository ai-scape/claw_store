# monitor_companies.ps1 — Monitor AI company updates, save to DB
param(
    [string]$Company = "",      # e.g. "Nvidia", "OpenAI"
    [string]$OutputDir = ""     # defaults to config
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$OutputDir) { $OutputDir = "$DB_COMPANIES/$($Company.ToLower())" }
if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$timestamp = Get-Date -Format "yyyy-MM-dd"
$logFile = "$LOG_DIR/companies_$($Company.ToLower())_$timestamp.log"

function Write-Log {
    param($Level, $Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $logFile -Append
}

function Get-CompanyRSS {
    param($company)
    
    $rssMap = @{
        "Nvidia"          = @{
            blog = "https://blogs.nvidia.com/feed/"
            rss  = "https://blogs.nvidia.com/feed/"
            twitter = "@NvidiaAI"
        }
        "OpenAI"          = @{
            blog = "https://openai.com/news/rss/"
            twitter = "@OpenAI"
            changelog = "https://help.openai.com/en/articles/6825453-chatgpt-release-notes"
        }
        "Google DeepMind" = @{
            blog = "https://deepmind.google/discover/blog/"
            twitter = "@GoogleDeepMind"
            papers = "https://deepmind.google/blog/rss.xml"
        }
        "Runway"          = @{
            blog = "https://research.runwayml.com/blog"
            twitter = "@runwayml"
            changelog = "https://techcrunch.com/tag/runway/"
        }
        "Luma AI"         = @{
            twitter = "@LumaLabsAI"
            blog = "https://lumalabs.ai/blog"
        }
        "Sora"            = @{
            twitter = "@OpenAI"
            site = "https://openai.com/sora"
        }
        "Kling"           = @{
            site = "https://klingai.com"
            twitter = "@KlingAIOfficial"
        }
        "Minimax Hailuo"  = @{
            blog = "https://www.minimax.io/news/minimax-m27-en"
            twitter = "@MinimaxIO"
            github = "https://github.com/MiniMax-AI/MiniCPM-V-2"
        }
        "Vidu"            = @{
            site = "https://www.vidu.studio"
            twitter = "@Vidu_EA"
        }
        "Alibaba Qwen"    = @{
            blog = "https://qwenlm.github.io/blog/"
            github = "https://github.com/QwenLM/Qwen"
            twitter = "@Qwen_AI"
            modelscope = "https://www.modelscope.cn/home"
        }
        "Alibaba Wan"     = @{
            site = "https://wan.space.alibaba.com"
            blog = "https://www.alibabacloud.com/blog"
        }
        "ByteDance Seed"  = @{
            site = "https://team.douban.com/"
            twitter = "@ByteDance"
            github = "https://github.com/bytedance/seed"
        }
        "Z AI"            = @{
            site = "https://z-ai.com"
            twitter = "@Z_Ai_Yi"
            github = "https://github.com/z-ai/ziya"
        }
        "Moonshot AI"     = @{
            site = "https:// moonshot.ai"
            twitter = "@Moonshot_AI"
            blog = "https://kimi.moonshot.cn/docs"
        }
        "Mistral"         = @{
            blog = "https://mistral.ai/news/"
            twitter = "@MistralAI"
            github = "https://github.com/mistralai/mistral-finetune"
        }
        "Higgsfield"      = @{
            twitter = "@higgsfield_ai"
            site = "https://higgsfield.jumpstarter.io"
            changelog = "https://higgsfield.io/whats-new"
        }
        "Freepik"         = @{
            twitter = "@Freepik"
            site = "https://www.freepik.com"
            blog = "https://www.freepik.com/blog/category/ai/"
        }
        "OpenArt"         = @{
            twitter = "@openart_ai"
            site = "https://openart.ai"
        }
        "InVideo"         = @{
            twitter = "@InVideo_Official"
            site = "https://invideo.io"
            blog = "https://invideo.io/blog/"
        }
    }
    
    return $rssMap[$company]
}

function Get-BlogContent {
    param($company, $url)
    
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UserAgent "Mozilla/5.0 (compatible; AIIntel/1.0)"
        $html = $response.Content
        
        # Extract article titles and links from RSS/HTML
        $items = @()
        
        # Try RSS first
        if ($html -match '<\?xml|<rss|<feed') {
            [xml]$rss = $html
            if ($rss.rss.channel.item) {
                foreach ($item in $rss.rss.channel.item | Select-Object -First 5) {
                    $items += @{
                        title = $item.title.Trim()
                        link = $item.link.Trim()
                        date = if ($item.pubDate) { [DateTime]::Parse($item.pubDate).ToString("yyyy-MM-dd") } else { "" }
                        desc = $item.description -replace '<[^>]+>', '' | ForEach-Object { $_.Trim() } | Select-Object -First 300
                    }
                }
            }
        }
        else {
            # Try Atom
            if ($html -match '<entry>') {
                # Atom format
                $entryRegex = '<entry>.*?<title>([^<]+)</title>.*?<link[^>]+href="([^"]+)"[^>]*/>.*?<published>([^<]+)</published>.*?</entry>'
                $matches = [regex]::Matches($html, $entryRegex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                foreach ($m in $matches | Select-Object -First 5) {
                    $items += @{
                        title = $m.Groups[1].Value.Trim()
                        link = $m.Groups[2].Value.Trim()
                        date = [DateTime]::Parse($m.Groups[3].Value.Trim()).ToString("yyyy-MM-dd")
                        desc = ""
                    }
                }
            }
        }
        
        return $items
    }
    catch {
        Write-Log "WARN" "Failed to fetch $url : $($_.Exception.Message)"
        return @()
    }
}

function Get-TwitterXUpdates {
    param($company, $handle)
    
    # Use web fetch for X profiles (public, no auth needed for highlights)
    try {
        $url = "https://nitter.net/$($handle.TrimStart('@'))"
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UserAgent "Mozilla/5.0" -UseBasicParsing
        # Parse recent tweets from nitter (RSS alternative)
        return @{ handle = $handle; success = $true }
    }
    catch {
        return @{ handle = $handle; success = $false; note = "Nitter unavailable, skipping X fetch" }
    }
}

# ── MAIN ───────────────────────────────────────────────────
Write-Log "INFO" "=== Starting company monitoring: $Company ==="

$info = Get-CompanyRSS -company $Company
if (!$info) {
    Write-Log "ERROR" "Unknown company: $Company"
    return
}

$reportFile = "$OutputDir/$($timestamp)_report.md"
$entries = @()

# 1. Blog/RSS
foreach ($key in @("blog", "rss", "papers")) {
    if ($info[$key]) {
        Write-Log "INFO" "Fetching $($info[$key])..."
        $items = Get-BlogContent -company $Company -url $info[$key]
        foreach ($item in $items) {
            $entries += $item
            
            # Save individual item
            if ($item.link) {
                $slug = $item.link -replace '[^a-z0-9]', '-' | ForEach-Object { $_.Substring(0, [Math]::Min(50, $_.Length)) }
                $itemFile = "$OutputDir/$($timestamp)_$($slug).md"
                $content = @()
                $content += "# $($item.title)"
                $content += "**Company:** $Company  |  **Date:** $($item.date)"
                $content += "**Source:** [$($info[$key])]($($info[$key]))"
                $content += "**Link:** [$($item.link)]($($item.link))"
                $content += ""
                $content += "## Description"
                $content += $item.desc
                $content += ""
                $content += "---"
                $content += "_Fetched by AI Intel System on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') IST_"
                $content | Out-File -FilePath $itemFile -Encoding UTF8
            }
        }
        Write-Log "INFO" "Found $($items.Count) items from $key"
    }
}

# 2. Twitter/X handle
if ($info.twitter) {
    Write-Log "INFO" "Checking Twitter: $($info.twitter)"
    # Will be enhanced with Nitter/podfollow fallback
}

# 3. GitHub
if ($info.github) {
    try {
        $ghApi = "https://api.github.com/repos/$($info.github -replace 'https://github.com/', '')"
        $gh = Invoke-RestMethod -Uri $ghApi -TimeoutSec 10
        $entries += @{
            title = "GitHub: $($gh.name)"
            link = $gh.html_url
            date = [DateTime]::Parse($gh.updated_at).ToString("yyyy-MM-dd")
            desc = "$($gh.description) | Stars: $($gh.stargazers_count) | Lang: $($gh.language)"
        }
        Write-Log "INFO" "GitHub: $($gh.name) ($($gh.stargazers_count) stars)"
    }
    catch {
        Write-Log "WARN" "GitHub fetch failed: $($_.Exception.Message)"
    }
}

# ── Build Report ────────────────────────────────────────────
$report = @()
$report += "# AI Company Monitor — $Company"
$report += "**Date:** $(Get-Date -Format 'yyyy-MM-dd')  |  ** IST:** $(Get-Date -Format 'HH:mm')"
$report += ""
$report += "## Updates This Session"
$report += ""
if ($entries.Count -eq 0) {
    $report += "_No updates found this session._"
}
else {
    foreach ($e in $entries) {
        $report += "- **$($e.title)** ($($e.date))"
        if ($e.desc) { $report += "  - $($e.desc)" }
        if ($e.link) { $report += "  - $($e.link)" }
        $report += ""
    }
}
$report += ""
$report += "---"
$report += "_Generated by AI Intel System — Ayush's AI Monitor_"

$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Log "INFO" "Report saved: $reportFile ($($entries.Count) entries)"

# Return summary
return @{
    company = $Company
    date = $timestamp
    entries = $entries.Count
    reportFile = $reportFile
}
