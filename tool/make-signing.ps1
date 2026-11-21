<#
.SYNOPSIS
  Creates the Android release keystore for Vyapari in a private folder
  outside the repo, plus everything GitHub Actions and local builds need.

.DESCRIPTION
  Writes to <PrivateDir>\signing (default D:\Vyapari-private\signing):
    release.jks          the keystore - BACK THIS UP; every update must use it
    release.jks.b64      base64 copy, the value for ANDROID_KEYSTORE_BASE64
    github-secrets.txt   the four repository secrets as NAME=value lines
  and points packages/app/android/key.properties (git-ignored) at the
  keystore so `flutter build apk --release` signs locally too.

  Passwords are random and are never printed to the console.
  Refuses to overwrite an existing keystore.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\make-signing.ps1
  powershell -ExecutionPolicy Bypass -File tool\make-signing.ps1 -Upload   # also sets the GitHub secrets via gh
#>
param(
  [string]$PrivateDir = 'D:\Vyapari-private',
  [string]$Alias = 'vyapari',
  [string]$DName = 'CN=Vyapari, OU=Games, O=Vyapari, C=IN',
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $PrivateDir 'signing'
$jks = Join-Path $dir 'release.jks'
$b64 = Join-Path $dir 'release.jks.b64'
$secrets = Join-Path $dir 'github-secrets.txt'
$keyProps = Join-Path $repo 'packages\app\android\key.properties'

if ($dir.StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) {
  throw "PrivateDir must be outside the repo ($repo)."
}
if (Test-Path $jks) {
  throw "$jks already exists. Move it away first if you really want a new key (installed apps will then need uninstalling)."
}

$keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { 'keytool' }
if (-not (Get-Command $keytool -ErrorAction SilentlyContinue)) { throw 'keytool not found; install a JDK or set JAVA_HOME.' }

function New-Password {
  # 32 chars from letters and digits only: safe in properties files, shells and YAML.
  $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}
# PKCS12 keystores use one password for store and key.
$pass = New-Password

New-Item -ItemType Directory -Force $dir | Out-Null
# keytool writes progress to stderr; Windows PowerShell turns that into an
# error under 'Stop', so relax it just for the native call.
$ErrorActionPreference = 'Continue'
& $keytool -genkeypair -keystore $jks -storetype PKCS12 -alias $Alias `
  -keyalg RSA -keysize 2048 -validity 10000 -dname $DName `
  -storepass $pass -keypass $pass 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $jks)) { throw 'keytool failed to create the keystore.' }

$encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jks))
[IO.File]::WriteAllText($b64, $encoded)

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($secrets, @"
# GitHub -> repo Settings -> Secrets and variables -> Actions -> New repository secret
# Created $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Keep this folder private and backed up.
ANDROID_KEYSTORE_BASE64=<contents of release.jks.b64>
ANDROID_KEYSTORE_PASSWORD=$pass
ANDROID_KEY_ALIAS=$Alias
ANDROID_KEY_PASSWORD=$pass
"@, $utf8)

# Local release builds: gradle resolves storeFile relative to android/app.
$storeFile = $jks -replace '\\', '/'
[IO.File]::WriteAllText($keyProps, "storeFile=$storeFile`nstorePassword=$pass`nkeyAlias=$Alias`nkeyPassword=$pass`n", $utf8)

Write-Host "Created in ${dir}:"
Get-ChildItem $dir | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }
Write-Host "Local signing: $keyProps (git-ignored)"
$ErrorActionPreference = 'Continue'
$fp = (& $keytool -list -keystore $jks -storepass $pass -alias $Alias 2>$null | Select-String 'SHA-256|SHA256').Line
$ErrorActionPreference = 'Stop'
if ($fp) { Write-Host "Certificate $($fp.Trim())" }

if ($Upload) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh CLI not found; add the secrets by hand from github-secrets.txt.' }
  Push-Location $repo
  try {
    $encoded | gh secret set ANDROID_KEYSTORE_BASE64
    $pass | gh secret set ANDROID_KEYSTORE_PASSWORD
    $Alias | gh secret set ANDROID_KEY_ALIAS
    $pass | gh secret set ANDROID_KEY_PASSWORD
    Write-Host 'Uploaded the four ANDROID_* secrets to GitHub.'
  } finally { Pop-Location }
} else {
  Write-Host "Next: add the four secrets from $secrets to GitHub (paste release.jks.b64 as ANDROID_KEYSTORE_BASE64)."
}
