# ai-intel.psm1 - AI Intelligence Monitoring PowerShell Module

$ErrorActionPreference = 'Continue'
$script:BaseDir = Split-Path -Parent $PSScriptRoot

# =============================================================================
# Config
# =============================================================================
$script:Config = @{
    TokenFile   = "$env:USERPROFILE\.openclaw\workspace\.secrets\telegram_bot_token.txt"
    DBBase      = "$script:BaseDir\db"
    ReportBase  = "$script:BaseDir\reports"
    LogBase     = "$script:BaseDir\logs"
    TimeZone    = 'Asia/Kolkata'
}

# =============================================================================
# Helpers
# =============================================================================
function Get-Token {
    $f = $script:Config.TokenFile
    if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null }
}

function Get-DBPath {
    param($Category)
    $p = "$($script:Config.DBBase)\$Category"
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    "$p\$(Get-Date -Format 'yyyy-MM-dd').json"
}

function Assert-MinimalDeps {
    # Ensure required directories exist
    foreach ($dir in $script:Config.DBBase, $script:Config.ReportBase, $script:Config.LogBase) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}

# =============================================================================
# Telegram
# =============================================================================
function Send-TelegramMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$ChatID = '7739622002'
    )
    $token = Get-Token
    if (-not $token) { Write-Warning '[Telegram] No token found'; return }
    $text = [System.Uri]::EscapeDataString($Message)
    $uri = "https://api.telegram.org/bot$token/sendMessage?chat_id=$ChatID&text=$text"
    try {
        $j = Invoke-RestMethod -Uri $uri -TimeoutSec 15 -ErrorAction Stop
        if ($j.ok) { Write-Host "[Telegram] Sent OK (msg_id=$($j.result.message_id))" }
        else { Write-Warning "[Telegram] API error: $($j.description)" }
    } catch {
        Write-Warning "[Telegram] Failed: $_"
    }
}

# =============================================================================
# DB Operations
# =============================================================================
function Add-DatabaseEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][hashtable]$Entry,
        [string]$KeyField = 'url'
    )
    Assert-MinimalDeps
    $file = Get-DBPath $Category
    $list = @()
    if (Test-Path $file) {
        try { $list = @((Get-Content $file -Raw) | ConvertFrom-Json) } catch { $list = @() }
        if ($list -and $list.GetType().Name -eq 'PSCustomObject') { $list = @($list) }
    }
    if ($KeyField -and $Entry.ContainsKey($KeyField)) {
        $keyVal = $Entry[$KeyField]
        if ($list | Where-Object { $_.$KeyField -eq $keyVal }) { return 'duplicate' }
    }
    $Entry['_added'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $list += $Entry
    $list | ConvertTo-Json -Depth 10 | Set-Content $file -Encoding UTF8
    'ok'
}

function Search-KnowledgeBase {
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Category,
        [int]$MaxAgeDays = 7,
        [int]$Limit = 20
    )
    Assert-MinimalDeps
    $pattern = "*-$((Get-Date).AddDays(-$MaxAgeDays).ToString('yyyy-MM-dd')).json"
    $filter = if ($Category) { "$($script:Config.DBBase)\$Category\$pattern" } else { "$($script:Config.DBBase)\*\$pattern" }
    $results = @()
    foreach ($f in Get-ChildItem $filter -ErrorAction SilentlyContinue) {
        try {
            $data = @((Get-Content $f.FullName -Raw) | ConvertFrom-Json)
            if ($data.GetType().Name -eq 'PSCustomObject') { $data = @($data) }
            $results += $data
        } catch { }
    }
    if ($Query) {
        $q = $Query.ToLower()
        $results = $results | Where-Object {
            ($_.title -like "*$q*") -or ($_.description -like "*$q*") -or ($_.name -like "*$q*") -or ($_.prompt -like "*$q*")
        }
    }
    $results | Select-Object -First $Limit
}

# =============================================================================
# RSS Fetcher
# =============================================================================
function Get-RSSFeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Selector = 'title',
        [int]$MaxItems = 20
    )
    try {
        [System.Xml.XmlDocument]$doc = New-Object System.Xml.XmlDocument
        $doc.Load($Url)
        $ns = @{ x = 'http://www.w3.org/2005/Atom' }
        $items = $doc.SelectNodes("//x:entry", $ns)
        if (-not $items.Count) {
            $items = $doc.SelectNodes('//item')
            if (-not $items.Count) { $items = $doc.SelectNodes('//entry') }
        }
        $count = 0
        foreach ($item in $items) {
            if ($count++ -ge $MaxItems) { break }
            $title = $item.SelectSingleNode('title').'#text'
            $link  = $item.SelectSingleNode('link/@href').'#text'
            if (-not $link) {
                $ln = $item.SelectSingleNode('link')
                $link = if ($ln) { $ln.'#text' } else { '' }
            }
            $desc = $item.SelectSingleNode('summary').'#text'
            if (-not $desc) { $desc = $item.SelectSingleNode('description') }
            $pub  = $item.SelectSingleNode('published') -or $item.SelectSingleNode('pubDate')
            $pubDate = if ($pub) { $pub.'#text' } else { '' }
            [PSCustomObject]@{
                title       = $title
                url         = $link
                description = $desc
                published   = $pubDate
            }
        }
    } catch {
        Write-Warning "RSS fetch failed for $Url : $_"
        @()
    }
}

# =============================================================================
# HTML Fetcher (basic)
# =============================================================================
function Get-HTMLContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Selector = 'article'
    )
    try {
        $html = Invoke-WebRequest -Uri $Url -UserAgent 'Mozilla/5.0' -TimeoutSec 15 | Select-Object -ExpandProperty Content
        # Very lightweight: just extract <title> and <a href> for now
        $title = [regex]::Match($html, '<title[^>]*>([^<]+)</title>').Groups[1].Value
        [PSCustomObject]@{ title = $title; url = $Url; raw = $html }
    } catch {
        Write-Warning "HTML fetch failed for $Url : $_"
        $null
    }
}

# =============================================================================
# Export all functions
# =============================================================================
Export-ModuleMember -Function @(
    'Send-TelegramMessage'
    'Add-DatabaseEntry'
    'Search-KnowledgeBase'
    'Get-RSSFeed'
    'Get-HTMLContent'
    'Get-DBPath'
    'Get-Token'
    'Assert-MinimalDeps'
)
