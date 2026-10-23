# Puts the JDK, Gradle and Android SDK that setup.ps1 installs on PATH for this PowerShell session.
# Usage: . tools/emulator/env.ps1
# JAVA_HOME and ANDROID_HOME, when already set, take precedence over the default locations.

$programs = Join-Path $env:LOCALAPPDATA 'Programs'
if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem $programs -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$gradle = Join-Path $programs 'gradle-9.8.2\bin'

$env:Path = @(
    (Join-Path $env:JAVA_HOME 'bin'),
    $gradle,
    (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    (Join-Path $env:ANDROID_HOME 'emulator'),
    $env:Path
) -join ';'
