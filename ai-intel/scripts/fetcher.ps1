# fetcher.ps1 — Universal fetch engine (Web → Markdown → DB)
param(
    [Parameter(Mandatory=$true)]
    [string]$Source,
    
    [Parameter(Mandatory=$true)]
    [string]$Type,  # company | paper | filmmaker | aggregator
    
    [string]$OutputDir = "$PSScriptRoot/../database/temp",
    [string]$Selector = "",
    [string]$ApiEndpoint = "",
    [string]$ApiMethod = "GET",
    [string]$ApiBody = "",
    [string]$RssUrl = ""
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

$srcSlug = $Source.ToLower() -replace '[^a-z0-9]', '-'
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$outFile = "$OutputDir/${srcSlug}_${timestamp}.md"

# ── RSS Mode ──────────────────────────────────────────────
if ($RssUrl) {
    try {
        $rss = Invoke-RestMethod -Uri $RssUrl -TimeoutSec 15 -UserAgent "PowerShell/5.1"
        $items = @()
        if ($rss.channel.item) {
            $rss.channel.item | ForEach-Object { $items += $_ }
        }
        
        $lines = @()
        $lines += "# $Source — Latest Papers"
        $lines += "_Fetched: $(Get-Date -Format 'yyyy-MM-dd HH:mm') IST_`n"
        $lines += "**Source:** [$RssUrl]($RssUrl)`n"
        $lines += ""
        $lines += "---`n`n"
        
        $count = 0
        foreach ($item in $items) {
            $count++
            $title = $item.title.Trim()
            $link = $item.link.Trim()
            $desc = $item.description -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&amp;', '&' | ForEach-Object { $_.Trim() } | Select-Object -First 200
            $pubDate = if ($item.pubDate) { [DateTime]::Parse($item.pubDate).ToString("yyyy-MM-dd") } else { "N/A" }
            $authors = if ($item.GetElementsByTagName("dc:creator")) { $item.GetElementsByTagName("dc:creator").'#text' } else { "" }
            
            $lines += "## [$count] $title"
            $lines += "**Published:** $pubDate  |  **Authors:** $authors"
            $lines += ""
            $lines += "**Link:** [$link]($link)"
            $lines += ""
            $lines += $desc
            $lines += ""
            $lines += "---`n`n"
        }
        
        $lines += "`n_Total: $($items.Count) papers fetched_"
        
        if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
        $lines | Out-File -FilePath $outFile -Encoding UTF8
        
        Write-Host "SUCCESS: $($items.Count) papers saved to $outFile"
        return @{ success = $true; count = $items.Count; file = $outFile }
    }
    catch {
        Write-Host "RSS ERROR: $($_.Exception.Message)"
        return @{ success = $false; error = $_.Exception.Message }
    }
}

# ── Web Selector Mode ──────────────────────────────────────
if ($Selector) {
    # Uses the embedded Chromium via Node/Playwright (via a JS helper)
    # Returns page text / structured content for the given CSS selector
    $nodeScript = @"
const { chromium } = require('playwright');
const url = process.argv[2];
const selector = process.argv[3];
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
  await page.waitForTimeout(2000);
  const content = await page.locator(selector).innerText().catch(() => '(not found)');
  console.log(JSON.stringify({ url, selector, content: content.substring(0, 8000) }));
  await browser.close();
})();
"@
    $tmpJs = "$env:TEMP\pwf_${srcSlug}_$PID.js"
    $nodeScript | Out-File -FilePath $tmpJs -Encoding UTF8
    $result = node $tmpJs $ApiEndpoint $Selector 2>&1
    Remove-Item $tmpJs -EA SilentlyContinue
    
    if ($LASTEXITCODE -eq 0 -and $result) {
        $parsed = $result | ConvertFrom-Json
        $lines = @()
        $lines += "# $Source — Fetched Content"
        $lines += "_Fetched: $(Get-Date -Format 'yyyy-MM-dd HH:mm') IST_`n"
        $lines += "**URL:** [$ApiEndpoint]($ApiEndpoint)`n"
        $lines += "**Selector:** `$($Selector)`n"
        $lines += "---`n`n"
        $lines += "```"
        $lines += $parsed.content
        $lines += "```"
        
        if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
        $lines | Out-File -FilePath $outFile -Encoding UTF8
        
        Write-Host "SUCCESS: Content saved"
        return @{ success = $true; file = $outFile; preview = $parsed.content.Substring(0, [Math]::Min(200, $parsed.content.Length)) }
    }
    else {
        Write-Host "PLAYWRIGHT ERROR: $($result)"
        return @{ success = $false; error = $result }
    }
}

Write-Host "No RssUrl or Selector provided. Use -RssUrl or -Selector."
return @{ success = $false; error = "No fetch mode specified" }
