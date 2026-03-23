$f = 'C:\Users\Welcome\.openclaw\workspace\ai-intel\scripts\monitor_papers.ps1'
$b = [System.IO.File]::ReadAllBytes($f)
$utf8 = [System.Text.Encoding]::UTF8
$withBom = $utf8.GetPreamble() + $b
[System.IO.File]::WriteAllBytes($f, $withBom)
Write-Host "BOM added to $f"
