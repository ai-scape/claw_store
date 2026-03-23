$f = 'C:\Users\Welcome\.openclaw\workspace\ai-intel\scripts\monitor_papers.ps1'
$b = [System.IO.File]::ReadAllBytes($f)
# Show first 5 lines bytes
$text = [System.Text.Encoding]::UTF8.GetString($b)
$text.Substring(0, [Math]::Min(500, $text.Length))
