$token = '8664233886:AAFG_Rz8jrP49udZkj_U4VU-JCZUTM4vJg0'
$msg = @"
📋 AI Search Evolution — Last Week Summary

1️⃣ PageRank (2000s) — link signals, no language understanding
2️⃣ Knowledge Graph (2012) — 500M entities, search knows what you mean
3️⃣ RankBrain (2015) — deep learning handles never-seen queries
4️⃣ BERT (2019) — bidirectional context, nuance returns
5️⃣ MUM (2021) — multimodal, multilingual, multi-step reasoning
6️⃣ SGE/AI Overviews (2023-24) — synthesis woven into results

Key takeaway: gap from research → production shrinks every year.

Full write-up: https://github.com/Hetid/ai-intel/blob/main/reports/ai_search_summary_2025-03-23.md
"@
$encoded = [System.Uri]::EscapeDataString($msg)
$uri = "https://api.telegram.org/bot$token/sendMessage?chat_id=7739622002&text=$encoded"
$r = Invoke-RestMethod -Uri $uri -TimeoutSec 15
Write-Host ($r | ConvertTo-Json -Depth 5)
