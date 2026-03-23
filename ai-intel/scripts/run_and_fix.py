import subprocess, os

base = r'C:\Users\Welcome\.openclaw\workspace\ai-intel\scripts'
bom  = b'\xef\xbb\xbf'

# Fix BOM on send_summary.ps1
ss_path = base + r'\send_summary.ps1'
ss = open(ss_path, 'r', encoding='utf-8').read()
with open(ss_path, 'wb') as f:
    f.write(bom + ss.encode('utf-8'))
print('BOM fixed: send_summary.ps1')

# Fix BOM on monitor_papers.ps1
mp_path = base + r'\monitor_papers.ps1'
mp = open(mp_path, 'r', encoding='utf-8').read()
with open(mp_path, 'wb') as f:
    f.write(bom + mp.encode('utf-8'))
print('BOM fixed: monitor_papers.ps1')

# Run send_summary.ps1
print('Running send_summary.ps1...')
r = subprocess.run(
    ['powershell', '-ExecutionPolicy', 'Bypass', '-File', ss_path],
    capture_output=True, text=True, timeout=30
)
print('STDOUT:', r.stdout)
if r.stderr:
    print('STDERR:', r.stderr[:500])
print('Return code:', r.returncode)
