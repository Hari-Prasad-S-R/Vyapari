#Requires -RunAsAdministrator
# Installs everything needed to build the Vyapari Android app, for all users:
#   - Eclipse Temurin JDK 21      -> C:\Program Files\Eclipse Adoptium
#   - Android SDK (API 36, NDK)   -> C:\Program Files\Android\Sdk
# and sets JAVA_HOME / ANDROID_HOME / PATH machine-wide.
#
# You will be asked to accept two licenses yourself:
#   1. the Temurin JDK package agreement (winget)
#   2. the Android SDK License Agreement (sdkmanager --licenses)
#
# Run from an elevated PowerShell:
#   powershell -ExecutionPolicy Bypass -File D:\Vyapari-dev\vyapari\tool\install-android-sdk.ps1

$ErrorActionPreference = 'Stop'
$sdk = 'C:\Program Files\Android\Sdk'
$toolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
$packages = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358')
$flutter = 'D:\flutter\bin\flutter.bat'

function Add-MachinePath([string]$dir) {
  $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  if (-not ($path -split ';' | Where-Object { $_ -ieq $dir })) {
    [Environment]::SetEnvironmentVariable('Path', "$path;$dir", 'Machine')
  }
  $env:Path = "$env:Path;$dir"
}

Write-Host '== 1/5  Java JDK 21 (accept the package agreement when asked) ==' -ForegroundColor Cyan
winget install --id EclipseAdoptium.Temurin.21.JDK --exact --scope machine
$jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory |
  Where-Object Name -like 'jdk-21*' | Sort-Object Name -Descending | Select-Object -First 1
if (-not $jdk) { throw 'JDK 21 not found under C:\Program Files\Eclipse Adoptium' }
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk.FullName, 'Machine')
$env:JAVA_HOME = $jdk.FullName
Add-MachinePath "$($jdk.FullName)\bin"
& "$($jdk.FullName)\bin\java.exe" -version

Write-Host '== 2/5  Android SDK command-line tools ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Force "$sdk\cmdline-tools" | Out-Null
$zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
$unpack = Join-Path $env:TEMP 'android-cmdline-tools'
Invoke-WebRequest $toolsUrl -OutFile $zip -UseBasicParsing
Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip $unpack -Force
Remove-Item "$sdk\cmdline-tools\latest" -Recurse -Force -ErrorAction SilentlyContinue
Move-Item "$unpack\cmdline-tools" "$sdk\cmdline-tools\latest"
Remove-Item $zip, $unpack -Recurse -Force -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'Machine')
$env:ANDROID_HOME = $sdk
Add-MachinePath "$sdk\cmdline-tools\latest\bin"
Add-MachinePath "$sdk\platform-tools"
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"

Write-Host '== 3/5  Android SDK License Agreement (read and answer y) ==' -ForegroundColor Cyan
& $sdkmanager "--sdk_root=$sdk" --licenses

Write-Host '== 4/5  SDK platform 36, build-tools, platform-tools, NDK (~2-3 GB) ==' -ForegroundColor Cyan
& $sdkmanager "--sdk_root=$sdk" @packages

Write-Host '== 5/5  Point Flutter at the SDK ==' -ForegroundColor Cyan
& $flutter config --android-sdk $sdk
& $flutter config --jdk-dir $jdk.FullName
& $flutter doctor

Write-Host ''
Write-Host 'Done. Open a NEW terminal so the new PATH/JAVA_HOME/ANDROID_HOME apply.' -ForegroundColor Green
