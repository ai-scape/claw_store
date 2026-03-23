$f = 'C:\Users\Welcome\.openclaw\workspace\ai-intel\scripts\monitor_papers.ps1'
# Read with UTF8, write back with UTF8 (adds BOM)
$content = Get-Content $f -Encoding UTF8 -Raw
$bom = [System.Text.Encoding]::UTF8.GetPreamble()
$body = [System.Text.Encoding]::UTF8.GetBytes($content)
[System.IO.File]::WriteAllBytes($f, $bom + $body)
Write-Host "Fixed encoding on $f"
