# monitor_papers.ps1 - ArXiv paper monitoring
param(
    [string]$Category = "cs.AI",
    [int]$MaxResults = 20
)
$ErrorActionPreference = 'Continue'
$BaseDir = Split-Path -Parent $PSScriptRoot

# Load config (dot-source so $script: vars land in our scope)
. "$BaseDir\scripts\config.ps1"

$logDir = "$LOG_DIR"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$dbBase = "$DB_BASE"
if (-not (Test-Path $dbBase)) { New-Item -ItemType Directory -Path $dbBase -Force | Out-Null }

function Get-ArXivFeed {
    param([string]$Cat, [int]$Max = 20)
    $url = "http://export.arxiv.org/api/query?search_query=cat:$Cat&max_results=$Max&sortBy=submittedDate&sortOrder=descending"
    try {
        [System.Xml.XmlDocument]$doc = New-Object System.Xml.XmlDocument
        $doc.Load($url)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
        $nsMgr.AddNamespace('a', 'http://www.w3.org/2005/Atom')
        $doc.SelectNodes('//a:entry', $nsMgr) | ForEach-Object {
            $entry = $_
            $titleNode = $entry.SelectSingleNode('a:title', $nsMgr)
            $t = if ($titleNode) { $titleNode.'#text' -replace '\s+', ' ' } else { '' }
            $sumNode = $entry.SelectSingleNode('a:summary', $nsMgr)
            $sum = if ($sumNode) { ($sumNode.'#text' -replace '\s+', ' ').Trim() } else { '' }
            $authNodes = $entry.SelectNodes('a:name', $nsMgr)
            $auths = @($authNodes | ForEach-Object { $_.'#text' })
            $pubNode = $entry.SelectSingleNode('a:published', $nsMgr)
            $published = if ($pubNode) { $pubNode.'#text' } else { '' }
            $updNode = $entry.SelectSingleNode('a:updated', $nsMgr)
            $updated = if ($updNode) { $updNode.'#text' } else { '' }
            $idNode = $entry.SelectSingleNode('a:id', $nsMgr)
            $id = if ($idNode) { $idNode.'#text' } else { '' }
            $pdfNodes = $entry.SelectNodes('a:link', $nsMgr)
            $pdfLink = ''
            foreach ($ln in $pdfNodes) {
                $titleAttr = $ln.Attributes.GetNamedItem('title')
                if ($titleAttr -and $titleAttr.Value -eq 'pdf') {
                    $pdfLink = $ln.GetAttribute('href')
                    break
                }
            }
            [PSCustomObject]@{
                title       = $t
                url         = $id
                description = $sum
                authors     = $auths -join ', '
                published   = $published
                updated     = $updated
                pdf_url     = $pdfLink
            }
        }
    } catch {
        Write-Warning "ArXiv feed error for $Cat : $_"
        @()
    }
}

function Save-Paper {
    param([PSCustomObject]$Paper, [string]$Tag)
    $safeTag = ($Tag -replace '[^a-zA-Z0-9_\-]', '_')
    $tagDir = "$dbBase\$safeTag"
    if (-not (Test-Path $tagDir)) { New-Item -ItemType Directory -Path $tagDir -Force | Out-Null }
    $ymd = (Get-Date -Format 'yyyy-MM-dd')
    $file = "$tagDir\$ymd.json"
    $list = @()
    if (Test-Path $file) {
        try { $list = @((Get-Content $file -Raw) | ConvertFrom-Json) } catch { $list = @() }
        if ($list -and $list.GetType().Name -eq 'PSCustomObject') { $list = @($list) }
    }
    $key = $Paper.url
    if ($list | Where-Object { $_.url -eq $key }) { return 'duplicate' }
    $entry = [ordered]@{
        title       = $Paper.title
        url         = $Paper.url
        description = $Paper.description
        authors     = $Paper.authors
        published   = $Paper.published
        pdf_url     = $Paper.pdf_url
        tag         = $Tag
        _added      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    }
    $list += $entry
    $list | ConvertTo-Json -Depth 10 | Set-Content $file -Encoding UTF8
    'ok'
}

# Map friendly names to arXiv category codes
$arxivMap = @{
    "ArXiv CS.AI"       = "cs.AI"
    "ArXiv CS.CV"       = "cs.CV"
    "ArXiv CS.CL"       = "cs.CL"
    "ArXiv CS.LG"       = "cs.LG"
    "HuggingFace Papers" = "cs.AI"
}

# Determine which categories to check
$catsToCheck = @()
if ($Category) {
    # Specific category passed
    $code = $arxivMap[$Category]
    if (-not $code) { $code = $Category }
    $catsToCheck = @($code)
} else {
    # Default: check all configured categories
    $catsToCheck = @('cs.AI', 'cs.CV', 'cs.CL', 'cs.LG')
}

foreach ($catCode in $catsToCheck) {
    $friendly = ($arxivMap.GetEnumerator() | Where-Object { $_.Value -eq $catCode }).Key
    if (-not $friendly) { $friendly = $catCode }
    Write-Host "Checking ArXiv $friendly..."
    $papers = Get-ArXivFeed -Cat $catCode -Max $MaxResults
    $saved = 0
    foreach ($paper in $papers) {
        $result = Save-Paper -Paper $paper -Tag $friendly
        if ($result -eq 'ok') {
            $saved++
            $short = $paper.title.Substring(0, [Math]::Min(60, $paper.title.Length))
            Write-Host "  [NEW] $short"
        }
    }
    Write-Host "  -> $saved new papers saved for $friendly"
}

Write-Host "Generating daily report..."
$allPapers = @()
foreach ($dir in Get-ChildItem $dbBase -Directory) {
    $todayFile = "$($dir.FullName)\$(Get-Date -Format 'yyyy-MM-dd').json"
    if (Test-Path $todayFile) {
        try {
            $data = @(Get-Content $todayFile -Raw | ConvertFrom-Json)
            if ($data -and $data.GetType().Name -eq 'PSCustomObject') { $data = @($data) }
            $allPapers += $data
        } catch {}
    }
}

if ($allPapers.Count -gt 0) {
    $report = "# AI Research Papers - $(Get-Date -Format 'yyyy-MM-dd')`n`n"
    $report += "*Automated daily digest from ArXiv*`n`n"
    $report += "Total new papers today: $($allPapers.Count)`n`n"
    $report += "---\n"
    foreach ($paper in ($allPapers | Sort-Object published)) {
        $authors = if ($paper.authors.Length -gt 80) { $paper.authors.Substring(0, 77) + '...' } else { $paper.authors }
        $pubDate = if ($paper.published) { $paper.published.Substring(0, 10) } else { 'N/A' }
        $report += "## $($paper.title)`n`n"
        $report += "- **Authors:** $authors`n"
        $report += "- **Published:** $pubDate`n"
        $report += "- **Category:** $($paper.tag)`n"
        $report += "- **Links:** [Paper]($($paper.url)) | [PDF]($($paper.pdf_url))`n"
        $report += "- **Abstract:** $($paper.description.Substring(0, [Math]::Min(300, $paper.description.Length)))...`n`n"
    }
    $reportDir = "$BaseDir\reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $reportFile = "$reportDir\papers_daily_$(Get-Date -Format 'yyyy-MM-dd').md"
    $report | Set-Content $reportFile -Encoding UTF8
    Write-Host "Report written: $reportFile ($($allPapers.Count) papers)"
} else {
    Write-Host "No new papers found."
}
Write-Host "Done."
