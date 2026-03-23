# report_weekly.ps1 — Compile and send weekly video + daily digests
param(
    [string]$OutputDir = "",
    [string]$Period = "weekly",  # weekly | daily
    [switch]$SendToUser
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$OutputDir) { $OutputDir = $DB_REPORTS }

$timestamp = Get-Date -Format "yyyy-MM-dd"
$logFile = "$LOG_DIR/report_${period}_${timestamp}.log"

function Write-Log {
    param($Level, $Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $logFile -Append
}

# ── Collect latest files ───────────────────────────────────
function Get-DBFiles {
    param($SubDir, $DaysBack = 7, $Extension = ".md")
    
    $path = "$DB_BASE/$SubDir"
    if (!(Test-Path $path)) { return @() }
    
    $cutoff = (Get-Date).AddDays(-$DaysBack)
    $files = Get-ChildItem -Path $path -Recurse -Filter "*$Extension" | Where-Object { $_.LastWriteTime -gt $cutoff }
    return $files
}

Write-Log "INFO" "=== Compiling $Period report ==="

# ── Fetch latest theAISearch video ───────────────────────
Write-Log "INFO" "Fetching latest theAISearch video..."
$ytScript = @"
const { chromium } = require('playwright');
const url = 'https://www.youtube.com/@theAIsearch/videos';
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
  await page.waitForTimeout(3000);
  
  // Get first video link
  const firstVideo = await page.locator('ytd-rich-item-renderer a#video-title-link').first().getAttribute('href').catch(() => null);
  const firstTitle = await page.locator('ytd-rich-item-renderer a#video-title-link').first().innerText().catch(() => '');
  const firstMeta = await page.locator('ytd-rich-item-renderer span#metadata-line').first().innerText().catch(() => '');
  
  console.log(JSON.stringify({ url: firstVideo, title: firstTitle, meta: firstMeta }));
  await browser.close();
})();
"@

$tmpJs = "$env:TEMP\yt_latest_$PID.js"
$ytScript | Out-File -FilePath $tmpJs -Encoding UTF8
$ytResult = node $tmpJs 2>&1
Remove-Item $tmpJs -EA SilentlyContinue

$videoData = @{ title = "(unknown)"; url = ""; meta = "" }
if ($LASTEXITCODE -eq 0 -and $ytResult) {
    try { $videoData = $ytResult | ConvertFrom-Json } catch {}
}

Write-Log "INFO" "Latest video: $($videoData.title)"

# ── Build report ──────────────────────────────────────────
$reportDate = Get-Date -Format "yyyy-MM-dd"
$reportFile = "$OutputDir/${period}_${reportDate}.md"

$report = @()
$report += if ($Period -eq "weekly") {
    "# 🎬 AI Intelligence — Weekly Report"
} else {
    "# 🤖 AI Intelligence — Daily Digest"
}
$report += "**Period:** $reportDate  |  **IST:** $(Get-Date -Format 'HH:mm')"
$report += ""

# ── Section 1: Latest theAISearch Video ──────────────────
if ($videoData.url) {
    $report += "## 📺 theAISearch — Latest Video"
    $report += "**[$($videoData.title)]($($videoData.url))**"
    $report += "_$($videoData.meta)_"
    $report += ""
    $report += "Watch: https://www.youtube.com$($videoData.url)"
    $report += ""
    $report += "---`n"
}
$report += ""

# ── Section 2: Company Updates (last 7 days) ─────────────
$companyFiles = Get-DBFiles -SubDir "companies" -DaysBack (if ($Period -eq "weekly") { 7 } else { 2 })
if ($companyFiles) {
    $report += "## 🏢 Company Updates"
    $report += ""
    
    $byCompany = @{}
    foreach ($f in $companyFiles) {
        $company = $f.Directory.Name
        if (!$byCompany[$company]) { $byCompany[$company] = @() }
        $byCompany[$company] += $f
    }
    
    foreach ($company in $byCompany.Keys | Sort-Object) {
        $latest = $byCompany[$company] | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $content = Get-Content $latest.FullName -Raw -Encoding UTF8
        $report += "### $company"
        # Extract first few bullets
        $lines = $content -split "`n" | Where-Object { $_ -match '^\-' } | Select-Object -First 5
        foreach ($l in $lines) { $report += $l }
        $report += ""
    }
    $report += "---`n"
}

# ── Section 3: Research Papers ───────────────────────────
$papersFiles = Get-DBFiles -SubDir "papers" -DaysBack (if ($Period -eq "weekly") { 7 } else { 2 })
if ($papersFiles) {
    $report += "## 📚 Research Papers (ArXiv)"
    $report += "_Latest from cs.AI, cs.CV, cs.CL, cs.LG_`n"
    
    $byTag = @{}
    foreach ($f in $papersFiles) {
        $tag = $f.Directory.Name
        if (!$byTag[$tag]) { $byTag[$tag] = @() }
        $byTag[$tag] += $f
    }
    
    foreach ($tag in $byTag.Keys | Sort-Object) {
        $report += "### $tag"
        foreach ($f in $byTag[$tag] | Sort-Object LastWriteTime -Descending | Select-Object -First 3) {
            $title = (Get-Content $f.FullName -First 1 -Encoding UTF8) -replace '^# ', ''
            $report += "- $title"
        }
        $report += ""
    }
    $report += "---`n"
}

# ── Section 4: AI Filmmakers ─────────────────────────────
$filmmakerFiles = Get-DBFiles -SubDir "filmmakers" -DaysBack (if ($Period -eq "weekly") { 7 } else { 2 })
$promptsFiles = Get-DBFiles -SubDir "filmmakers" -DaysBack (if ($Period -eq "weekly") { 7 } else { 1 }) -Extension "_prompts.md"
if ($filmmakerFiles) {
    $report += "## 🎨 AI Filmmakers & Prompts"
    $report += ""
    
    # Extract top Reddit posts
    $jsonFiles = $filmmakerFiles | Where-Object { $_.Extension -eq ".json" }
    foreach ($jf in $jsonFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1) {
        $posts = Get-Content $jf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $topPosts = $posts | Sort-Object -Property score -Descending | Select-Object -First 5
        foreach ($p in $topPosts) {
            $report += "- ⬆ **$($p.title)** (r/$($p.subreddit), $($p.score) pts)"
            if ($p.selftext) {
                $excerpt = $p.selftext.Substring(0, [Math]::Min(150, $p.selftext.Length))
                $report += "  > $excerpt..."
            }
            $report += ""
        }
    }
    
    # Best prompts
    foreach ($pf in $promptsFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1) {
        $content = Get-Content $pf.FullName -Raw -Encoding UTF8
        $promptLines = $content -split "`n" | Where-Object { $_ -match '\$ ' -or $_ -match '^##' } | Select-Object -First 10
        if ($promptLines) {
            $report += "### ✨ Cool Prompts"
            foreach ($pl in $promptLines) { $report += $pl }
            $report += ""
        }
    }
    $report += "---`n"
}

# ── Section 5: Aggregators ───────────────────────────────
$aggFiles = Get-DBFiles -SubDir "aggregators" -DaysBack (if ($Period -eq "weekly") { 7 } else { 2 })
if ($aggFiles) {
    $report += "## 🌐 AI Aggregators"
    $report += ""
    
    $bySource = @{}
    foreach ($f in $aggFiles) {
        $src = $f.Directory.Name
        if (!$bySource[$src]) { $bySource[$src] = @() }
        $bySource[$src] += $f
    }
    
    foreach ($src in $bySource.Keys | Sort-Object) {
        $latest = $bySource[$src] | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $report += "### $src"
        $lines = (Get-Content $latest.FullName -Encoding UTF8) -split "`n" | Where-Object { $_ -match '^\-' } | Select-Object -First 3
        foreach ($l in $lines) { $report += $l }
        $report += ""
    }
}

$report += ""
$report += "---"
$report += "_Generated by AI Intel System • Ayush's AI Monitor_"

$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Log "INFO" "Report saved: $reportFile"

# ── Send to user via Telegram ─────────────────────────────
if ($SendToUser) {
    try {
        $telegramScript = "$PSScriptRoot/send_telegram.ps1"
        if (Test-Path $telegramScript) {
            $summary = ($report | Select-Object -First 30) -join "`n"
            & $telegramScript -Message "📊 *$($Period.ToUpper()) AI REPORT — $reportDate*`n`n$summary`n`n📁 Full report: $reportFile"
            Write-Log "INFO" "Telegram sent"
        }
    }
    catch {
        Write-Log "ERROR" "Telegram send failed: $($_.Exception.Message)"
    }
}

Write-Log "INFO" "=== Report complete ==="
return @{ reportFile = $reportFile; period = $Period }
