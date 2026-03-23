# query_kb.ps1 — Search the knowledge base
param(
    [Parameter(Mandatory=$true)]
    [string]$Query,
    
    [string]$Category = "all",  # all | companies | papers | filmmakers | aggregators | videos
    [int]$MaxResults = 20,
    [switch]$Report,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$OutputDir) { $OutputDir = $DB_REPORTS }
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"

function Search-Files {
    param($Path, $Query, $Extensions = @(".md", ".json", ".txt"))
    
    if (!(Test-Path $Path)) { return @() }
    
    $results = @()
    foreach ($ext in $Extensions) {
        $files = Get-ChildItem -Path $Path -Recurse -Filter "*$ext" -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -and $content -match $Query) {
                    $lines = $content -split "`n"
                    $matchedLines = $lines | Where-Object { $_ -match $Query } | Select-Object -First 3
                    $results += @{
                        file = $f.FullName
                        relativePath = $f.FullName.Replace("$DB_BASE\", "")
                        lastModified = $f.LastWriteTime.ToString("yyyy-MM-dd")
                        matchedLines = $matchedLines
                        score = ([regex]::Matches($content, [regex]::Escape($Query), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
                    }
                }
            }
            catch {}
        }
    }
    return $results
}

Write-Host "Searching for: '$Query' in $Category..."
Write-Host ""

$allResults = @()

$searchPaths = if ($Category -eq "all") {
    @("companies", "papers", "filmmakers", "aggregators", "videos")
} else {
    @($Category)
}

foreach ($cat in $searchPaths) {
    $path = "$DB_BASE/$cat"
    $results = Search-Files -Path $path -Query $Query
    
    foreach ($r in $results) {
        $allResults += $r
    }
    
    Write-Host "  [$cat] → $($results.Count) matches"
}

# Sort by score
$sortedResults = $allResults | Sort-Object -Property score -Descending | Select-Object -First $MaxResults

# Build report
$reportFile = "$OutputDir/search_${timestamp}.md"
$report = @()
$report += "# Knowledge Base Search — ""$Query"""
$report += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm') IST  |  **Results:** $($sortedResults.Count)"
$report += ""
$report += "---`n"

if ($sortedResults.Count -eq 0) {
    $report += "_No results found. Try different keywords._`n"
}
else {
    $currentFile = ""
    foreach ($r in $sortedResults) {
        if ($r.relativePath -ne $currentFile) {
            $report += "## 📄 $($r.relativePath)"
            $report += "_Last modified: $($r.lastModified) | Score: $($r.score)_`n"
            $currentFile = $r.relativePath
        }
        
        foreach ($line in $r.matchedLines) {
            $highlighted = $line -replace "([^*]*)$Query([^*]*)", '$1**$2**' 2>$null
            $report += "> $line"
        }
        $report += ""
    }
}

$report += "---"
$report += "_AI Intel Knowledge Base — searched $(Get-Date -Format 'yyyy-MM-dd HH:mm')_"

$report | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "Found $($sortedResults.Count) results → $reportFile"

# Print top results to console
foreach ($r in $sortedResults | Select-Object -First 10) {
    Write-Host ""
    Write-Host "$($r.relativePath) ($($r.score) matches)"
    foreach ($line in $r.matchedLines | Select-Object -First 2) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 120) { $trimmed = $trimmed.Substring(0, 120) + "..." }
        Write-Host "  → $trimmed"
    }
}

return @{
    query = $Query
    total = $sortedResults.Count
    reportFile = $reportFile
    topResults = $sortedResults | Select-Object -First 10
}
