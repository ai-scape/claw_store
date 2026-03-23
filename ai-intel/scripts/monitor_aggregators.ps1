# monitor_aggregators.ps1 — Track AI aggregators & their curated content
param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$OutputDir) { $OutputDir = $DB_AGGREGATORS }

$timestamp = Get-Date -Format "yyyy-MM-dd"
$logFile = "$LOG_DIR/aggregators_${timestamp}.log"
$reportFile = "$OutputDir/$($timestamp)_aggregators_report.md"

function Write-Log {
    param($Level, $Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $logFile -Append
}

$aggregators = @{
    "Higgsfield" = @{
        name = "Higgsfield AI"
        url = "https://higgsfield.jumpstarter.io"
        blog = "https://higgsfield.io/whats-new"
        twitter = "@higgsfield_ai"
        desc = "AI image & video generation platform, curated showcase"
    }
    "Freepik" = @{
        name = "Freepik AI"
        url = "https://www.freepik.com"
        blog = "https://www.freepik.com/blog/category/artificial-intelligence/"
        twitter = "@Freepik"
        desc = "AI image generator with large template library"
    }
    "OpenArt" = @{
        name = "OpenArt"
        url = "https://openart.ai"
        twitter = "@openart_ai"
        desc = "AI image generation with style presets and community prompts"
    }
    "InVideo" = @{
        name = "InVideo AI"
        url = "https://invideo.io"
        blog = "https://invideo.io/blog/"
        twitter = "@InVideo_Official"
        desc = "AI video creation from text prompts"
    }
}

Write-Log "INFO" "=== Aggregator Monitor: $(Get-Date -Format 'yyyy-MM-dd') ==="

$allUpdates = @()

foreach ($key in $aggregators.Keys) {
    $agg = $aggregators[$key]
    Write-Log "INFO" "Checking: $key..."
    
    # Fetch blog/updates page
    if ($agg.blog) {
        try {
            $response = Invoke-WebRequest -Uri $agg.blog -TimeoutSec 15 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            $html = $response.Content
            
            # Extract article titles, dates, links
            $items = @()
            
            # WordPress/RSS style
            if ($html -match '<item>|atom:entry') {
                [xml]$rss = $html
                if ($rss.rss.channel.item) {
                    $rss.rss.channel.item | Select-Object -First 5 | ForEach-Object {
                        $items += @{
                            title = $_.title.Trim()
                            link = $_.link.Trim()
                            date = try { [DateTime]::Parse($_.pubDate).ToString("yyyy-MM-dd") } catch { "" }
                            desc = $_.description -replace '<[^>]+>', '' | ForEach-Object { $_.Trim() } | Select-Object -First 200
                        }
                    }
                }
            }
            else {
                # Parse HTML article cards
                $titleRegex = '<h[23][^>]*>\s*<a[^>]+>([^<]+)</a>'
                $linkRegex = '<a[^>]+href="([^"]+)"[^>]*>\s*<img|href="([^"]+)"[^>]*>[^<]*<h[23]'
                # Simple title extraction
                $titleMatches = [regex]::Matches($html, '<h[23][^>]*>(?:<[^>]+>)*\s*([^<]+)')
                $linkMatches = [regex]::Matches($html, 'href="(https?://[^"]+)"[^>]*>(?:[^<]*<){0,3}h[23]')
                
                $c = 0
                foreach ($tm in $titleMatches | Select-Object -First 5) {
                    $title = $tm.Groups[1].Value.Trim()
                    if ($title.Length -gt 10) {
                        $items += @{
                            title = $title
                            link = "See page"
                            date = ""
                            desc = ""
                        }
                        $c++
                    }
                }
            }
            
            foreach ($item in $items) {
                $entry = @{
                    source = $key
                    title = $item.title
                    link = $item.link
                    date = $item.date
                    desc = $item.desc
                }
                $allUpdates += $entry
                
                # Save individual
                if ($item.link -and $item.link -ne "See page") {
                    $slug = $item.title -replace '[^a-z0-9]', '-' | ForEach-Object { $_.Substring(0, [Math]::Min(40, $_.Length)) }
                    $itemFile = "$OutputDir/$($key.ToLower())/$($timestamp)_$($slug).md"
                    if (!(Test-Path (Split-Path $itemFile))) { New-Item -ItemType Directory -Path (Split-Path $itemFile) -Force | Out-Null }
                    
                    $content = @()
                    $content += "# $($item.title)"
                    $content += "**Source:** $key  |  **Date:** $($item.date)"
                    $content += "**URL:** [$($item.link)]($($item.link))"
                    $content += ""
                    $content += "## Summary"
                    $content += $item.desc
                    $content += ""
                    $content += "---"
                    $content += "_Fetched: $(Get-Date -Format 'yyyy-MM-dd HH:mm') IST_"
                    $content | Out-File -FilePath $itemFile -Encoding UTF8
                }
            }
            
            Write-Log "INFO" "  → $($items.Count) updates from $key"
        }
        catch {
            Write-Log "WARN" "  → Failed to fetch $key : $($_.Exception.Message)"
        }
    }
    
    Start-Sleep -Seconds 1
}

# Build report
$report = @()
$report += "# AI Aggregator Monitor — $(Get-Date -Format 'yyyy-MM-dd')"
$report += ""
$report += "## Updates Today ($($allUpdates.Count) total)"
$report += ""

$bySource = @{}
foreach ($u in $allUpdates) {
    if (!$bySource[$u.source]) { $bySource[$u.source] = @() }
    $bySource[$u.source] += $u
}

foreach ($src in $bySource.Keys | Sort-Object) {
    $report += "### $src"
    $report += "_$($aggregators[$src].desc)_`n"
    foreach ($u in $bySource[$src]) {
        $report += "- **$($u.title)**"
        if ($u.date) { $report += " _($($u.date))_" }
        if ($u.desc) { $report += "  - $($u.desc)" }
        if ($u.link -ne "See page") { $report += "  [$($u.link)]($($u.link))" }
        $report += ""
    }
    $report += ""
}

$report += "---"
$report += "_Generated by AI Intel System_"

$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Log "INFO" "Report saved: $reportFile"

return @{
    date = $timestamp
    total = $allUpdates.Count
    reportFile = $reportFile
}
