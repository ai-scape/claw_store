# dispatcher.ps1 — Master dispatcher: routes to all monitors based on day/time
param(
    [string]$RunMode = "auto",   # auto | companies | papers | filmmakers | aggregators | video | report
    [string]$DayOverride = "",   # Manual day selection (for testing)
    [switch]$SendReport
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot/config.ps1"

# Init
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$logFile = "$LOG_DIR/dispatcher_${timestamp}.log"

if (!(Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }
if (!(Test-Path "$DB_BASE")) { New-Item -ItemType Directory -Path "$DB_BASE" -Force | Out-Null }

function Write-Log {
    param($Level, $Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "$ts [$Level] $Msg"
    Write-Host $line
    $line | Out-File -FilePath $logFile -Append
}

function Invoke-Script {
    param($Script, $Params = @{})
    
    $paramStr = $Params.Keys | ForEach-Object { "-$_ $($Params[$_])" } | ForEach-Object { "$_" }
    $fullCmd = "pwsh -File `"$Script`" $paramStr"
    Write-Log "INFO" "RUNNING: $fullCmd"
    
    $result = & pwsh -File $Script @Params 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "INFO" "SUCCESS: $Script"
    }
    else {
        Write-Log "ERROR" "FAILED: $Script — $($result | Select-Object -First 5)"
    }
    return $result
}

# ── DAY SCHEDULE ─────────────────────────────────────────
$dayOfWeek = if ($DayOverride) { $DayOverride } else { (Get-Date).DayOfWeek }

Write-Log "INFO" "=== AI Intel Dispatcher ==="
Write-Log "INFO" "Run Mode: $RunMode | Day: $dayOfWeek | Time: $(Get-Date -Format 'HH:mm') IST ==="

# Always create base dirs
@($DB_COMPANIES, $DB_PAPERS, $DB_FILMMAKERS, $DB_AGGREGATORS, $DB_VIDEOS, $DB_REPORTS) | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

$results = @{}

# ── COMPANIES (daily) ───────────────────────────────────
if ($RunMode -eq "auto" -or $RunMode -eq "companies") {
    $todaysCompanies = $DAILY_COMPANIES[$dayOfWeek.ToString()]
    
    if ($todaysCompanies) {
        Write-Log "INFO" "Today is $dayOfWeek — companies: $($todaysCompanies -join ', ')"
        
        foreach ($company in $todaysCompanies) {
            Write-Log "INFO" "--- Monitoring: $company ---"
            
            $outDir = "$DB_COMPANIES/$($company.ToLower())"
            if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
            
            $r = Invoke-Script -Script "$PSScriptRoot/monitor_companies.ps1" -Params @{
                Company = $company
                OutputDir = $outDir
            }
            $results[$company] = if ($r) { "OK" } else { "FAIL" }
            
            Start-Sleep -Seconds 5
        }
    }
    else {
        Write-Log "INFO" "No companies scheduled for $dayOfWeek"
    }
}

# ── PAPERS (Mon/Wed/Fri/Sat) ─────────────────────────────
if ($RunMode -eq "auto" -or $RunMode -eq "papers") {
    $paperDays = @("Monday", "Wednesday", "Friday", "Saturday")
    
    if ($paperDays -contains $dayOfWeek.ToString()) {
        Write-Log "INFO" "Paper day: $dayOfWeek — fetching ArXiv..."
        
        foreach ($cat in @("cs.AI", "cs.CV", "cs.CL", "cs.LG")) {
            $r = Invoke-Script -Script "$PSScriptRoot/monitor_papers.ps1" -Params @{ Category = $cat; MaxResults = 20 }
            $results["papers_$cat"] = if ($r) { "OK" } else { "FAIL" }
            Start-Sleep -Seconds 3
        }
    }
}

# ── FILMMAKERS (Tue/Thu) ────────────────────────────────
if ($RunMode -eq "auto" -or $RunMode -eq "filmmakers") {
    $filmmakerDays = @("Tuesday", "Thursday")
    
    if ($filmmakerDays -contains $dayOfWeek.ToString()) {
        Write-Log "INFO" "Filmmaker day: $dayOfWeek"
        $r = Invoke-Script -Script "$PSScriptRoot/monitor_filmmakers.ps1"
        $results["filmmakers"] = if ($r) { "OK" } else { "FAIL" }
    }
}

# ── AGGREGATORS (Sat) ────────────────────────────────────
if ($RunMode -eq "auto" -or $RunMode -eq "aggregators") {
    if ($dayOfWeek.ToString() -eq "Saturday") {
        Write-Log "INFO" "Aggregator day: Saturday"
        $r = Invoke-Script -Script "$PSScriptRoot/monitor_aggregators.ps1"
        $results["aggregators"] = if ($r) { "OK" } else { "FAIL" }
    }
}

# ── VIDEO (Sunday) ──────────────────────────────────────
if ($RunMode -eq "auto" -or $RunMode -eq "video") {
    if ($dayOfWeek.ToString() -eq "Sunday") {
        Write-Log "INFO" "Video day: Sunday — fetching theAISearch latest..."
        $r = Invoke-Script -Script "$PSScriptRoot/monitor_video.ps1"
        $results["video"] = if ($r) { "OK" } else { "FAIL" }
    }
}

# ── REPORT ───────────────────────────────────────────────
if ($SendReport -or $RunMode -eq "report") {
    Write-Log "INFO" "Generating report..."
    
    $period = if ($dayOfWeek.ToString() -eq "Sunday") { "weekly" } else { "daily" }
    
    $r = Invoke-Script -Script "$PSScriptRoot/report_weekly.ps1" -Params @{
        Period = $period
        SendToUser = if ($SendReport) { $true } else { $false }
    }
    $results["report"] = if ($r) { "OK" } else { "FAIL" }
}

# ── Summary ───────────────────────────────────────────────
Write-Log "INFO" "=== Dispatcher complete ==="
foreach ($k in $results.Keys) {
    Write-Log "INFO" "  $_ = $($results[$k])"
}

return $results
