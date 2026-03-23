# send_telegram.ps1 — Send message to Telegram user (Ayush)
param(
    [Parameter(Mandatory=$true)]
    [string]$Message,
    
    [string]$ParseMode = "Markdown",
    [string]$ChatId = ""  # defaults to config
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

if (!$ChatId) { $ChatId = $PRIMARY_CHANNEL_ID }

$Message = $Message -replace '\$', '�'  # placeholder for markdown $

# Read bot token
$tokenFile = "$PSScriptRoot/../../.secrets/telegram_bot_token.txt"
if (!(Test-Path $tokenFile)) {
    Write-Host "ERROR: Bot token not found at $tokenFile"
    Write-Host "Create the file with your Telegram bot token."
    return @{ success = $false; error = "No bot token" }
}

$botToken = (Get-Content $tokenFile -Raw -Encoding UTF8).Trim()

# Send message
$url = "https://api.telegram.org/bot$botToken/sendMessage"
$body = @{
    chat_id = $ChatId
    text = $Message
    parse_mode = $ParseMode
    disable_web_page_preview = $false
} | ConvertTo-Json -Compress

try {
    $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 15
    if ($response.ok) {
        Write-Host "Telegram sent: $($response.result.message_id)"
        return @{ success = $true; message_id = $response.result.message_id }
    }
    else {
        Write-Host "Telegram error: $($response.description)"
        return @{ success = $false; error = $response.description }
    }
}
catch {
    Write-Host "HTTP error: $($_.Exception.Message)"
    return @{ success = $false; error = $_.Exception.Message }
}
