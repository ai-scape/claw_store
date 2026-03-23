# ============================================================
# monitor_video.ps1 — theAISearch YouTube channel monitor
# Uses Playwright + system Chrome to scrape video descriptions
# ============================================================
param(
    [int]$Days    = 7,
    [int]$MaxResults = 5,
    [switch]$ForceRefresh
)

$ErrorActionPreference = 'Stop'
$BASE = Split-Path -Parent $PSScriptRoot

# ---------- logging ----------
function Write-Log($level, $msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$level] $msg"
}

# ---------- fetch via Playwright (system Chrome) ----------
function Get-VideoData {
    param([int]$MaxResults)

    # Node script — cd to ai-intel so node_modules are found
    $nodeScript = @'
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu', '--window-size=1280,900']
  });
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1280, height: 900 });

  // Load the channel's VIDEOS tab
  await page.goto('https://www.youtube.com/@theAIsearch/videos', { timeout: 25000, waitUntil: 'domcontentloaded' });

  // Scroll to trigger lazy-loading of the video grid
  let richItems = 0, gridItems = 0;
  for (let i = 0; i < 12; i++) {
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(1200);
    richItems = await page.evaluate(() => document.querySelectorAll('ytd-rich-item-renderer').length);
    gridItems = await page.evaluate(() => document.querySelectorAll('ytd-grid-video-renderer').length);
    if (richItems > 0 || gridItems > 0) break;
  }

  // Prefer grid (desktop layout), fall back to rich (new layout)
  let videos = await page.evaluate((max) => {
    const selectors = ['ytd-grid-video-renderer', 'ytd-rich-item-renderer'];
    for (const sel of selectors) {
      const items = document.querySelectorAll(sel);
      if (items.length > 0) {
        return Array.from(items).slice(0, max).map(item => {
          let title = '', url = '', meta = '';
          if (sel === 'ytd-grid-video-renderer') {
            const linkEl = item.querySelector('h3 a');
            const metaEl = item.querySelector('#meta');
            title = linkEl ? linkEl.innerText.trim() : '';
            url   = linkEl ? linkEl.href : '';
            meta  = metaEl ? metaEl.innerText.replace(/\n/g, ' | ').trim() : '';
          } else {
            const titleEl = item.querySelector('#video-title');
            const link    = item.querySelector('a#thumbnail');
            const metaEl  = item.querySelector('#meta');
            title = titleEl ? titleEl.innerText.trim() : '';
            url   = link   ? link.href : '';
            meta  = metaEl ? metaEl.innerText.replace(/\n/g, ' | ').trim() : '';
          }
          return { title, url, meta };
        });
      }
    }
    return [];
  }, $MaxResults);

  const latest = videos.find(v => v.url && v.url.includes('/watch?v=')) || videos[0];
  if (!latest || !latest.url) {
    console.log('ERROR:NO_VIDEOS');
    await browser.close();
    return;
  }

  // Navigate to the video page to get description
  await page.goto(latest.url, { timeout: 20000, waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);

  const description = await page.evaluate(() => {
    const el = document.querySelector('#description-inline-expander');
    if (el) return el.innerText;
    // Fallback: older layout
    const fallback = document.querySelector('#description-wrapper');
    return fallback ? fallback.innerText : '';
  });

  const result = { title: latest.title, url: latest.url, meta: latest.meta, description: description || '' };
  console.log('DATA:' + JSON.stringify(result));
  await browser.close();
})();
"@

    $tmpJs = [System.IO.Path]::GetTempFileName() + '.js'
    $nodeScript | Out-File -FilePath $tmpJs -Encoding UTF8 -NoNewline

    Push-Location 'C:\Users\Welcome\.openclaw\workspace\ai-intel'
    $result = node $tmpJs 2>&1
    Pop-Location
    Remove-Item $tmpJs -Force -ErrorAction SilentlyContinue

    if ($result -match 'DATA:(.+)') {
        $json = $matches[1]
        return ($json | ConvertFrom-Json)
    }
    Write-Log "ERROR" "Playwright fetch failed. Output: $result"
    return $null
}

# ---------- extract links from text ----------
function Get-LinksFromText($text) {
    $pattern = 'https?://[^\s<>)"'']+'
    $links   = [regex]::Matches($text, $pattern) | ForEach-Object { $_.Value } | Select-Object -Unique
    return @($links)
}

# ---------- main ----------
Write-Log "INFO" "Starting theAISearch monitor (Days=$Days, ForceRefresh=$ForceRefresh)"

$reportFile = Join-Path $BASE "reports\video_report_$(Get-Date -Format 'yyyy-MM-dd').md"
$stateFile  = Join-Path $BASE "state\video_state.json"

if (-not $ForceRefresh -and (Test-Path $stateFile)) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    Write-Log "INFO" ("Using cached state — last video: {0}" -f $state.lastVideoTitle)
}

Write-Log "INFO" "Fetching latest video via Playwright..."
$video = Get-VideoData -MaxResults $MaxResults

if (-not $video) {
    Write-Log "ERROR" "No video data returned from theAISearch channel"
    exit 1
}

Write-Log "INFO" ("Got video: {0}" -f $video.title)
$links = Get-LinksFromText $video.description
Write-Log "INFO" ("Extracted {0} links" -f $links.Count)

# save state
$stateDir = Split-Path -Parent $stateFile
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
@{
    lastVideoUrl    = $video.url
    lastVideoTitle  = $video.title
    lastChecked     = (Get-Date).ToString('o')
    checkedCount    = if ($state) { $state.checkedCount + 1 } else { 1 }
} | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8

# build report
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$report = @()
$report += "# theAISearch — Latest Video"
$report += ""
$report += "**Fetched:** $timestamp  |  **IST:** $(Get-Date -Format 'HH:mm')"
$report += ""
$report += "## Video"
$report += ("**[{0}]({1})**" -f $video.title, $video.url)
$report += ""
$report += ("**Meta:** {0}" -f $video.meta)
$report += ""
$report += "## Description"
$report += '```'
$report += $video.description
$report += '```'
$report += ""
$report += "## Links Found"
if ($links.Count -gt 0) {
    foreach ($link in $links) {
        $report += "- $link"
    }
} else {
    $report += "_No links found in description._"
}
$report += ""
$report += "---"
$report += "_Generated by AI Intel Monitor | theAISearch channel_"

$reportDir = Split-Path -Parent $reportFile
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
$report | Set-Content $reportFile -Encoding UTF8

Write-Log "INFO" ("Report written: {0}" -f $reportFile)
Write-Log "INFO" ("DONE: {0} | {1} links extracted" -f $video.title, $links.Count)

Write-Output "TITLE=$($video.title)"
Write-Output "URL=$($video.url)"
Write-Output "LINKS=$($links.Count)"
