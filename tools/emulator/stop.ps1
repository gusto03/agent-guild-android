# Shuts an emulator down cleanly and waits for its processes to exit, then stops the DNS forwarder
# when no emulator is left.
# Usage: pwsh tools/emulator/stop.ps1 [-Port 5554]

param([int]$Port = 5554)
. (Join-Path $PSScriptRoot 'env.ps1')

function Get-Emulator([string]$filter) {
    # Leaves out the helper an emulator starts to end its own process after a timeout (emulator -kill <pid> -sleep <s>).
    Get-CimInstance Win32_Process -Filter "Name = 'emulator.exe' OR Name LIKE 'qemu-system-x86_64%'" |
        Where-Object { $_.CommandLine -like $filter -and $_.CommandLine -notlike '* -kill *' }
}

adb -s "emulator-$Port" emu kill 2>$null | Out-Null

# The emulator keeps running for a while after adb loses it, and a new one started meanwhile fails.
$deadline = (Get-Date).AddSeconds(90)
while (Get-Emulator "*-port $Port *") {
    if ((Get-Date) -gt $deadline) { throw "The emulator on port $Port did not exit." }
    Start-Sleep 1
}

if (-not (Get-Emulator '*')) {
    $pidFile = Join-Path ([IO.Path]::GetTempPath()) 'agent-guild-android\dns-forward.pid'
    if (Test-Path $pidFile) {
        Stop-Process -Id (Get-Content $pidFile) -ErrorAction SilentlyContinue
        Remove-Item $pidFile
    }
}
