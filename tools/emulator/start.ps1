# Starts an emulator and waits until Android has booted.
# Usage: pwsh tools/emulator/start.ps1 [-Avd ag37] [-Port 5554] [-Tailnet] [-Window]
#   -Tailnet  also starts dns-forward.mjs, so the emulator resolves ts.net names.
#   -Window   shows the emulator's window; without it the emulator runs headless.
# Stop it with stop.ps1, never by killing the process: a killed emulator leaves a crash report
# whose consent dialog hangs the next boot.

param(
    [string]$Avd = 'ag37',
    [int]$Port = 5554,
    [switch]$Tailnet,
    [switch]$Window
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')

$serial = "emulator-$Port"
$avdHome = if ($env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME } else { Join-Path $HOME '.android\avd' }
$logs = Join-Path ([IO.Path]::GetTempPath()) 'agent-guild-android'
New-Item -ItemType Directory -Force $logs | Out-Null

# Left behind when an emulator did not shut down cleanly.
Get-ChildItem (Join-Path $avdHome "$Avd.avd") -Filter '*.lock' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem (Join-Path ([IO.Path]::GetTempPath()) 'AndroidEmulator') -Filter 'emu-crash-*.db' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

$arguments = @('-avd', $Avd, '-port', $Port, '-no-snapshot', '-gpu', 'host', '-no-boot-anim', '-no-metrics', '-crash-report-mode', 'never')
if (-not $Window) { $arguments += '-no-window' }
if ($Tailnet) {
    $pidFile = Join-Path $logs 'dns-forward.pid'
    $running = (Test-Path $pidFile) -and (Get-Process -Id (Get-Content $pidFile) -ErrorAction SilentlyContinue)
    if (-not $running) {
        $forwarder = Start-Process node -ArgumentList "`"$(Join-Path $PSScriptRoot 'dns-forward.mjs')`"" -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $logs 'dns-forward.log') -RedirectStandardError (Join-Path $logs 'dns-forward.err')
        Set-Content $pidFile $forwarder.Id
    }
    $arguments += '-dns-server', '127.0.0.1'
}

Start-Process emulator -ArgumentList $arguments -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logs "$Avd.log") -RedirectStandardError (Join-Path $logs "$Avd.err") | Out-Null

$deadline = (Get-Date).AddMinutes(4)
while ((adb -s $serial shell getprop sys.boot_completed 2>$null) -ne '1') {
    if ((Get-Date) -gt $deadline) { throw "$Avd did not boot; see $logs\$Avd.log" }
    Start-Sleep 2
}
# The network comes up after the boot completes, and drops again while Android settles on a default network.
$streak = 0
while ($streak -lt 5) {
    if ((Get-Date) -gt $deadline) { throw "$Avd booted, but its network did not settle" }
    # Only the name lookup counts: the older system images get no ICMP replies.
    $streak = if ((adb -s $serial shell ping -c 1 -W 2 dns.google 2>$null) -match '^PING dns\.google \(') { $streak + 1 } else { 0 }
    Start-Sleep 2
}
Write-Host "$Avd booted as $serial, with its network up"
