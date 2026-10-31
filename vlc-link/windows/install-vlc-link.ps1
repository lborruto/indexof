# VLC Link for Windows: makes vlc://files.lan:8099/... links (the files page's [vlc]) open in
# VLC, as http://files.lan:8099/... (the page leaves http out: Chrome rewrites vlc://http://...). For this Windows account only, no administrator needed. Run once, in PowerShell:
#   powershell -ExecutionPolicy Bypass -File install-vlc-link.ps1
# Only links to the files page (files.lan, its Tailscale name or 192.168.1.10, port 8099,
# under /media/ or /share/) are opened, so no other page can make VLC open what it likes.
$ErrorActionPreference = 'Stop'
$vlc = @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vlc) { Write-Host 'VLC is not installed (videolan.org): install it first.'; exit 1 }

$dir = Join-Path $env:LOCALAPPDATA 'vlc-link'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$open = Join-Path $dir 'open.ps1'
@'
param([string]$u)
# A link from the page is percent-encoded: no space, quote or other character VLC or a shell
# could read otherwise.
$ok = '^vlc://((files.lan|files.lan\.example-tailnet\.ts\.net|192\.168\.0\.15):8099/(media|share)/[A-Za-z0-9%._~/?&=:+-]+)$'
if ($u -notmatch $ok) { exit 1 }
$url = 'http://' + $Matches[1]
$vlc = @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($vlc) { Start-Process -FilePath $vlc -ArgumentList ('"' + $url + '"') }
'@ | Set-Content -Encoding UTF8 -Path $open

$key = 'HKCU:\Software\Classes\vlc'
New-Item -Force -Path "$key\shell\open\command" | Out-Null
Set-ItemProperty -Path $key -Name '(Default)' -Value 'URL:VLC link'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$key\shell\open\command" -Name '(Default)' -Value ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $open + '" "%1"')
Write-Host "Installed: vlc:// links now open in VLC ($vlc)."
