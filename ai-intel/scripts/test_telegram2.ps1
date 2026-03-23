$token = '8664233886:AAFG_Rz8jrP49udZkj_U4VU-JCZUTM4vJg0'
$msg = 'AI Intel test plain text only'
$encoded = [System.Uri]::EscapeDataString($msg)
$uri = "https://api.telegram.org/bot$token/sendMessage?chat_id=7739622002&text=$encoded"
Write-Host "URI: $uri"

# Try as GET with -Uri
try {
    $r = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 15
    Write-Host "Invoke-RestMethod OK"
    Write-Host ($r | ConvertTo-Json -Depth 5)
} catch {
    Write-Host "Invoke-RestMethod Error: $($_.Exception.Message)"
}

# Also try plain Webrequest
try {
    $wr = [System.Net.WebRequest]::Create($uri)
    $wr.Method = 'GET'
    $wr.Timeout = 15000
    $resp = $wr.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $body = $sr.ReadToEnd()
    $sr.Close()
    Write-Host "WebRequest OK: $body"
} catch {
    Write-Host "WebRequest Error: $($_.Exception.Message)"
}
