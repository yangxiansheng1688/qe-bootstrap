# QuantEdge bootstrap: download deploy assets from GitHub release, then run deploy_final.ps1
# Feedback: webhook.site beacon at each stage. No secrets inside (token read from server file).
$ErrorActionPreference = 'Continue'
$bk = 'https://webhook.site/696ee0af-7124-46fa-bd80-f802bcb6364a'
$D  = 'C:\quantedge\_deploy'
$log = 'C:\quantedge\bootstrap.log'
function L($m) { Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $m) }
function BK($s) { try { curl.exe -s -m 15 ($bk + '?step=' + $s) | Out-Null } catch {} }

L '=== bootstrap start ==='
BK 'g0-started'
try { New-Item -ItemType Directory -Force -Path $D | Out-Null } catch {}
try { $t = Get-Content 'C:\quantedge\ops\gh\token.txt' -Raw; $t = $t.Trim() } catch { $t = '' }
if (-not $t) { L 'FATAL no token'; BK 'g0-fatal-notoken'; exit 1 }
L ('token loaded len=' + $t.Length)
$hdr = @{ Authorization = 'Bearer ' + $t; Accept = 'application/octet-stream'; 'User-Agent' = 'qe' }

try {
    $rel = Invoke-RestMethod -Headers $hdr -Uri 'https://api.github.com/repos/yangxiansheng1688/quantedge-deploy-ready/releases/tags/deploy1' -TimeoutSec 60
    L ('release assets: ' + $rel.assets.Count)
    foreach ($a in $rel.assets) {
        $out = Join-Path $D $a.name
        L ('downloading ' + $a.name + ' (' + [math]::Round($a.size/1MB,1) + 'MB)')
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Headers $hdr -Uri $a.url -OutFile $out -TimeoutSec 1800 -UseBasicParsing | Out-Null
        $sw.Stop()
        $got = (Get-Item $out).Length
        L ('  done bytes=' + $got + ' secs=' + [math]::Round($sw.Elapsed.TotalSeconds))
        BK ('g1-got-' + $a.name)
    }
} catch {
    L ('download fail: ' + $_.Exception.Message)
    BK 'g1-fail'
    exit 1
}

L 'all assets down; launching deploy_final.ps1'
BK 'g1-all-downloaded'
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $D 'deploy_final.ps1') 2>&1 | ForEach-Object { L ('deploy: ' + $_) }
    BK 'g2-deploy-ran'
} catch {
    L ('deploy fail: ' + $_.Exception.Message)
    BK 'g2-fail'
}
L '=== bootstrap end ==='
