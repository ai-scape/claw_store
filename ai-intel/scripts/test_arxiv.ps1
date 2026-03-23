$ErrorActionPreference = 'Continue'
$BaseDir = "C:\Users\Welcome\.openclaw\workspace\ai-intel"
$outFile = "$BaseDir\logs\test_output.log"
$null = New-Item -ItemType Directory -Path "$BaseDir\logs" -Force -ErrorAction SilentlyContinue

$log = ""
$fail = $false

$log += "=== Test start $(Get-Date) ===`n"

try {
    . "$BaseDir\scripts\config.ps1"
    $log += "Config loaded. DB_BASE=$DB_BASE`n"
} catch {
    $log += "Config FAILED: $_`n"
    $fail = $true
}

if (-not $fail) {
    try {
        $url = "http://export.arxiv.org/api/query?search_query=cat:cs.AI&max_results=1"
        $log += "Fetching: $url`n"
        [System.Xml.XmlDocument]$doc = New-Object System.Xml.XmlDocument
        $doc.Load($url)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
        $nsMgr.AddNamespace('a', 'http://www.w3.org/2005/Atom')
        $entries = $doc.SelectNodes('//a:entry', $nsMgr)
        $log += "Entries found: $($entries.Count)`n"
        if ($entries.Count -gt 0) {
            $t = $entries[0].SelectSingleNode('a:title', $nsMgr)
            $log += "First title: $($t.InnerText)`n"
        }
    } catch {
        $log += "ArXiv FAILED: $_`n"
    }
}

try {
    $dbBase = "$DB_BASE"
    if (-not (Test-Path $dbBase)) { New-Item -ItemType Directory -Path $dbBase -Force | Out-Null }
    $testFile = "$dbBase\test_write.json"
    @{ test = $true; date = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content $testFile -Encoding UTF8
    $log += "DB write OK: $testFile`n"
} catch {
    $log += "DB write FAILED: $_`n"
}

$log += "=== Test done ===`n"
$log | Set-Content $outFile -Encoding UTF8
Write-Host $log
