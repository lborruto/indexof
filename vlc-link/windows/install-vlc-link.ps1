# VLC Link for Windows: makes the page's vlc://host:port/... links (the [vlc] next to a video,
# "open in VLC" in the player) open in VLC, as http://host:port/... (the page leaves http out:
# Chrome rewrites vlc://http://...). For this Windows account only, no administrator needed.
# Run once, in PowerShell, with the page's addresses as they are in the browser's address bar
# (host:port), one or more, separated by commas; only links to those are opened:
#   powershell -ExecutionPolicy Bypass -File install-vlc-link.ps1 -Allowed files.example:8099,10.0.0.5:8099
# Run it again to change the list.
param([Parameter(Mandatory = $true)][string[]]$Allowed)
$ErrorActionPreference = 'Stop'

# The addresses: host:port (a name or an IPv4 address: letters, digits, dots, dashes, starting
# with a letter or a digit), nothing else; regex-escaped into the handler's pattern below.
$Allowed = @($Allowed -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if (-not $Allowed) { Write-Host 'Give the page''s addresses: -Allowed host:port,host:port'; exit 1 }
foreach ($o in $Allowed) {
    if ($o -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*:[0-9]{1,5}$') { Write-Host "Not an origin (host:port, with letters, digits, dots and dashes): $o"; exit 1 }
}
$origins = ($Allowed | ForEach-Object { [regex]::Escape($_) }) -join '|'

$vlc = @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vlc) { Write-Host 'VLC is not installed (videolan.org): install it first.'; exit 1 }

$dir = Join-Path $env:LOCALAPPDATA 'vlc-link'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$open = Join-Path $dir 'open.ps1'
# The handler: a link from the page only, that is one of the addresses given here, then a folder
# of the page, then a percent-encoded path and the link's query (no space, quote or other
# character VLC or a shell could read otherwise).
$handler = @'
param([string]$u)
# A link from the page only: one of the addresses given at install time, a folder of the page,
# then a percent-encoded path and the link's query.
$ok = '^vlc://((__ORIGINS__)/[A-Za-z0-9%._~-]+/[A-Za-z0-9%._~/?&=:+-]+)$'
if ($u -notmatch $ok) { exit 1 }
$url = 'http://' + $Matches[1]
$vlc = @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($vlc) { Start-Process -FilePath $vlc -ArgumentList ('"' + $url + '"') }
'@
$handler.Replace('__ORIGINS__', $origins) | Set-Content -Encoding UTF8 -Path $open

$key = 'HKCU:\Software\Classes\vlc'
New-Item -Force -Path "$key\shell\open\command" | Out-Null
Set-ItemProperty -Path $key -Name '(Default)' -Value 'URL:VLC link'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$key\shell\open\command" -Name '(Default)' -Value ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $open + '" "%1"')
Write-Host "Installed: vlc:// links to $($Allowed -join ', ') now open in VLC ($vlc)."
