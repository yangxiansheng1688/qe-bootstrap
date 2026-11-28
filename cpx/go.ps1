# ============================================================
# CryptoPulse Pro v11 incremental deploy (server-side bootstrap)
# Usage: powershell -ExecutionPolicy Bypass -File C:\cpx\go.ps1
# Flow : fetch 9 b64 shards from mirrors -> assemble update.zip
#        -> clean src/.next -> extract -> prisma db push
#        -> next build -> restart node -> schtasks auto-start
# ============================================================
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path C:\cpx -Force | Out-Null
$log = 'C:\cpx\upd-log.txt'
"UPD|START $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $log -Encoding utf8
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$mirrors = @(
  'https://raw.githubusercontent.com/yangxiansheng1688/qe-bootstrap/main/cpx/b64',
  'https://fastly.jsdelivr.net/gh/yangxiansheng1688/qe-bootstrap@main/cpx/b64',
  'https://gcore.jsdelivr.net/gh/yangxiansheng1688/qe-bootstrap@main/cpx/b64',
  'https://cdn.jsdelivr.net/gh/yangxiansheng1688/qe-bootstrap@main/cpx/b64'
)

function Fetch([string]$name, [string]$out) {
  foreach ($m in $mirrors) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri ($m + '/' + $name) -OutFile $out -TimeoutSec 40
      if ((Get-Item $out -ErrorAction SilentlyContinue).Length -gt 100) { return $true }
    } catch { }
  }
  return $false
}

# remove stale shards to avoid mixing old content
Remove-Item 'C:\cpx\b64part-*.txt' -Force -ErrorAction SilentlyContinue

$fetchOk = $true
for ($i = 0; $i -le 8; $i++) {
  $n = 'part-{0:d2}.txt' -f $i
  $o = 'C:\cpx\b64part-{0:d2}.txt' -f $i
  if (Fetch $n $o) { "UPD|FETCH-OK $n $((Get-Item $o).Length)" | Out-File $log -Append -Encoding utf8 }
  else { "UPD|FETCH-FAIL $n" | Out-File $log -Append -Encoding utf8; $fetchOk = $false }
}
if (-not $fetchOk) { "UPD|ABORT-fetch" | Out-File $log -Append -Encoding utf8; exit 1 }

$raw = ''
0..8 | ForEach-Object { $raw += [IO.File]::ReadAllText(('C:\cpx\b64part-{0:d2}.txt' -f $_)) }
$b64 = ($raw -replace '\s', '')
"UPD|B64LEN $($b64.Length)" | Out-File $log -Append -Encoding utf8
try {
  [IO.File]::WriteAllBytes('C:\cpx\update.zip', [Convert]::FromBase64String($b64))
} catch {
  "UPD|B64-ERR $_" | Out-File $log -Append -Encoding utf8; exit 1
}
$zlen = (Get-Item 'C:\cpx\update.zip').Length
"UPD|ZIPSIZE $zlen" | Out-File $log -Append -Encoding utf8
if ($zlen -ne 127695) { "UPD|ZIPSIZE-MISMATCH-abort" | Out-File $log -Append -Encoding utf8; exit 1 }

$env:Path = 'C:\Program Files\nodejs;' + $env:Path
Set-Location C:\CryptoPulsePro\app
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process | Where-Object { $_.ProcessName -match 'watchd|deploy-serv' } | Stop-Process -Force -ErrorAction SilentlyContinue
"UPD|KILLED" | Out-File $log -Append -Encoding utf8
Remove-Item 'C:\CryptoPulsePro\app\src' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\CryptoPulsePro\app\.next' -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path C:\cpx\update.zip -DestinationPath C:\CryptoPulsePro\app -Force
"UPD|EXTRACTED" | Out-File $log -Append -Encoding utf8
cmd /c "npx prisma db push >> C:\cpx\upd-log.txt 2>&1"
"UPD|PRISMA-DONE" | Out-File $log -Append -Encoding utf8
cmd /c "npm run build >> C:\cpx\upd-log.txt 2>&1"
"UPD|BUILD-DONE exit=$LASTEXITCODE" | Out-File $log -Append -Encoding utf8

# auto-start scheduled task (SYSTEM account)
$bat = "@echo off`r`nset PATH=C:\Program Files\nodejs;%PATH%`r`ncd /d C:\CryptoPulsePro\app`r`nnpm run start`r`n"
[IO.File]::WriteAllText('C:\cpx\start-app.bat', $bat)
schtasks /Create /TN CryptoPulsePro /TR 'C:\cpx\start-app.bat' /SC ONSTART /RU SYSTEM /RL HIGHEST /F 2>&1 | Out-File $log -Append -Encoding utf8

Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' -ArgumentList '/c', 'C:\cpx\start-app.bat > C:\cpx\app-out.log 2>&1'
Start-Sleep -Seconds 35
try { $t = New-Object Net.Sockets.TcpClient('127.0.0.1', 3000); $p = $t.Connected; $t.Close() } catch { $p = $false }
"UPD|FINAL p3000=$p" | Out-File $log -Append -Encoding utf8
if ($p) { 'UPD|DONE-OK' | Set-Clipboard } else { 'UPD|DONE-FAIL' | Set-Clipboard }
