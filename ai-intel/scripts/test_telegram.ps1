$token = '8664233886:AAFG_Rz8jrP49udZkj_U4VU-JCZUTM4vJg0'
$msg = '🔥 AI Intel module — ps5.1 compat OK'
$encoded = [System.Uri]::EscapeDataString($msg)
$uri = "https://api.telegram.org/bot$token/sendMessage?chat_id=7739622002&text=$encoded"
Write-Host "URI: $uri"
try {
    $r = Invoke-WebRequest -Uri $uri -Method Post -TimeoutSec 15
    Write-Host "Status: $($r.StatusCode)"
    Write-Host "Content: $($r.Content)"
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Response: $($_.Exception.Response)"
}
