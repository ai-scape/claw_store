# monitor_filmmakers.ps1 — Track AI filmmakers on Reddit, X, and prompts
param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$OutputDir) { $OutputDir = $DB_FILMMAKERS }

$timestamp = Get-Date -Format "yyyy-MM-dd"
$logFile = "$LOG_DIR/filmmakers_${timestamp}.log"
$reportFile = "$OutputDir/$($timestamp)_filmmakers_report.md"

function Write-Log {
    param($Level, $Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $logFile -Append
}

# ── Reddit via API ─────────────────────────────────────────
function Get-RedditPosts {
    param($subreddit, $sort = "hot", $limit = 10)
    
    $endpoints = @{
        "hot"     = "https://www.reddit.com/r/$subreddit/hot.json?limit=$limit"
        "new"     = "https://www.reddit.com/r/$subreddit/new.json?limit=$limit"
        "top"     = "https://www.reddit.com/r/$subreddit/top.json??t=week&limit=$limit"
    }
    
    $url = $endpoints[$sort]
    
    try {
        $headers = @{
            "User-Agent" = "PowerShell AI Intel/1.0 (by Ayush)"
            "Accept" = "application/json"
        }
        $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15
        $posts = @()
        
        $children = $response.data.children
        foreach ($child in $children) {
            $d = $child.data
            $post = @{
                subreddit = $d.subreddit
                title = $d.title
                author = $d.author
                score = $d.score
                url = $d.url
                selftext = if ($d.selftext) { $d.selftext -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' } else { "" }
                created_utc = [DateTime]::OffsetFromUnixTimeSeconds($d.created_utc).ToString("yyyy-MM-dd HH:mm")
                num_comments = $d.num_comments
                permalink = "https://reddit.com$($d.permalink)"
                is_video = $d.is_video
                link_flair_text = $d.link_flair_text
            }
            $posts += $post
        }
        
        return @{ success = $true; posts = $posts }
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message; subreddit = $subreddit }
    }
}

# ── X/Twitter via Nitter RSS ───────────────────────────────
function Get-NitterRSS {
    param($handle)
    
    $nitterInstances = @("nitter.net", "nitter.privacydev.net", "nitter.poast.org")
    
    foreach ($instance in $nitterInstances) {
        try {
            $url = "https://$instance/$($handle.TrimStart('@'))/rss"
            $rss = Invoke-RestMethod -Uri $url -TimeoutSec 10 -UserAgent "AIIntel/1.0"
            
            $items = @()
            if ($rss.channel.item) {
                $rss.channel.item | Select-Object -First 5 | ForEach-Object {
                    $items += @{
                        title = $_.title.Trim()
                        link = $_.link.Trim()
                        date = try { [DateTime]::Parse($_.pubDate).ToString("yyyy-MM-dd") } catch { "" }
                        desc = $_.description -replace '<[^>]+>', '' -replace 'http[^ ]+', '' | ForEach-Object { $_.Trim() }
                    }
                }
            }
            return @{ success = $true; instance = $instance; items = $items }
        }
        catch {
            continue
        }
    }
    
    return @{ success = $false; handle = $handle; note = "All Nitter instances failed" }
}

Write-Log "INFO" "=== Filmmaker Monitor: $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="

$allPosts = @()
$allTweets = @()
$coolPrompts = @()
$allSubs = $script:REDDIT_SUBREDDITS

# ── Fetch Reddit ───────────────────────────────────────────
foreach ($sub in $allSubs) {
    Write-Log "INFO" "Fetching Reddit: $sub..."
    
    $result = Get-RedditPosts -subreddit $sub -sort "hot" -limit 10
    
    if ($result.success) {
        $allPosts += $result.posts
        Write-Log "INFO" "  → $($result.posts.Count) posts from $sub"
        
        # Extract cool prompts (selftext with prompt-like content)
        foreach ($post in $result.posts) {
            if ($post.selftext -and $post.selftext.Length -gt 20) {
                # Detect if it looks like a prompt (contains common prompt keywords)
                $promptKeywords = @("prompt:", "generated with", "created using", "used", "seed", "sref", "cref", "style:", "model:", "gen:")
                $isPrompt = $false
                foreach ($kw in $promptKeywords) {
                    if ($post.selftext.ToLower() -match $kw) {
                        $isPrompt = $true
                        break
                    }
                }
                if ($isPrompt -and $post.score -gt 10) {
                    $coolPrompts += @{
                        subreddit = $sub
                        title = $post.title
                        prompt = $post.selftext
                        score = $post.score
                        url = $post.permalink
                        author = $post.author
                    }
                }
            }
        }
    }
    else {
        Write-Log "WARN" "  → Failed: $($result.error)"
    }
    
    Start-Sleep -Milliseconds 500
}

# ── Fetch X/Twitter ────────────────────────────────────────
foreach ($handle in $script:X_HANDLES) {
    Write-Log "INFO" "Fetching Nitter: $handle..."
    $result = Get-NitterRSS -handle $handle
    
    if ($result.success) {
        $allTweets += $result.items
        Write-Log "INFO" "  → $($result.items.Count) tweets from $handle"
    }
    else {
        Write-Log "WARN" "  → $($result.note)"
    }
    
    Start-Sleep -Milliseconds 300
}

# ── Save posts by source ──────────────────────────────────
$postsFile = "$OutputDir/$($timestamp)_reddit_posts.json"
$allPosts | ConvertTo-Json -Depth 5 | Out-File -FilePath $postsFile -Encoding UTF8

$promptsFile = "$OutputDir/$($timestamp)_prompts.md"
$promptReport = @()
$promptReport += "# Cool AI Prompts — $(Get-Date -Format 'yyyy-MM-dd')"
$promptReport += ""
$promptReport += "_Prompts extracted from Reddit (score > 10, keyword-detected)_`n"
$promptReport += ""

if ($coolPrompts.Count -gt 0) {
    $sortedPrompts = $coolPrompts | Sort-Object -Property score -Descending
    foreach ($p in $sortedPrompts) {
        $promptReport += "## $" + $p.title
        $promptReport += "**Subreddit:** r/$($p.subreddit)  |  **Score:** $($p.score)  |  **By:** $($p.author)"
        $promptReport += ""
        $promptReport += "```"
        $promptReport += $p.prompt
        $promptReport += "```"
        $promptReport += ""
        $promptReport += "🔗 $"
        $promptReport += ""
        $promptReport += "---`n"
    }
}
else {
    $promptReport += "_No prompts detected this session._"
}

$promptReport | Out-File -FilePath $promptsFile -Encoding UTF8

# ── Build Full Report ──────────────────────────────────────
$report = @()
$report += "# AI Filmmaker Monitor — $(Get-Date -Format 'yyyy-MM-dd')"
$report += "**Sources:** $(($allSubs | ForEach-Object { "r/$($_)" }) -join ', ')"
$report += ""
$report += "## Hot Posts This Week ($($allPosts.Count) total)"
$report += ""

# Group by subreddit
$bySub = @{}
foreach ($p in $allPosts) {
    if (!$bySub[$p.subreddit]) { $bySub[$p.subreddit] = @() }
    $bySub[$p.subreddit] += $p
}

foreach ($sub in $bySub.Keys | Sort-Object) {
    $report += "### r/$sub ($($bySub[$sub].Count) posts)`n"
    foreach ($p in $bySub[$sub] | Sort-Object -Property score -Descending | Select-Object -First 5) {
        $mediaTag = if ($p.is_video) { "📹" } else { "🖼️" }
        $report += "- $mediaTag **[$($p.title)]($($p.permalink))** (⬆ $($p.score))"
        if ($p.link_flair_text) { $report += " `[$p.link_flair_text`]" }
        $report += ""
    }
}

$report += ""
$report += "## X / Twitter Highlights"
$report += ""

if ($allTweets.Count -gt 0) {
    foreach ($t in $allTweets | Select-Object -First 10) {
        $report += "- **$($t.title)** ($($t.date))"
        if ($t.desc) { $report += "  - $($t.desc)" }
        $report += ""
    }
}
else {
    $report += "_No X updates fetched (Nitter instances unavailable)._`n"
}

$report += ""
$report += "## Cool Prompts ($($coolPrompts.Count) found)"
$report += "_See: $promptsFile_"
$report += ""
$report += "---"
$report += "_Generated by AI Intel System_"

$report | Out-File -FilePath $reportFile -Encoding UTF8

Write-Log "INFO" "=== Done: $($allPosts.Count) posts, $($coolPrompts.Count) prompts, $($allTweets.Count) tweets ==="

return @{
    date = $timestamp
    redditPosts = $allPosts.Count
    prompts = $coolPrompts.Count
    tweets = $allTweets.Count
    reportFile = $reportFile
    promptsFile = $promptsFile
}
