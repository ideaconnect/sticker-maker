# Idempotent installer: JDK 17 (Temurin), Flutter stable, Android cmdline-tools.
# No admin required; everything lands under $HOME\dev. Safe to re-run.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$dev = "$env:USERPROFILE\dev"
$tmp = "$env:TEMP\smtools"
New-Item -ItemType Directory -Force -Path $dev, $tmp | Out-Null

$jdkDir = "$dev\jdk-17"
$flutterDir = "$dev\flutter"
$sdk = "$dev\android-sdk"

function Log($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

# ---------- JDK 17 (Temurin) ----------
if (Test-Path "$jdkDir\bin\java.exe") {
  Log "JDK already present at $jdkDir"
} else {
  Log "Downloading Temurin JDK 17..."
  $jdkZip = "$tmp\jdk17.zip"
  curl.exe --fail --location --retry 3 --retry-delay 5 -o $jdkZip `
    "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
  Log "Extracting JDK..."
  $jx = "$tmp\jdk_x"; if (Test-Path $jx) { Remove-Item -Recurse -Force $jx }
  New-Item -ItemType Directory -Force -Path $jx | Out-Null
  tar -xf $jdkZip -C $jx
  $inner = Get-ChildItem $jx -Directory | Select-Object -First 1
  if (Test-Path $jdkDir) { Remove-Item -Recurse -Force $jdkDir }
  Move-Item $inner.FullName $jdkDir
  Log "JDK installed."
}
$env:JAVA_HOME = $jdkDir
$env:PATH = "$jdkDir\bin;$env:PATH"

# ---------- Flutter stable ----------
if (Test-Path "$flutterDir\bin\flutter.bat") {
  Log "Flutter already present at $flutterDir"
} else {
  Log "Resolving Flutter stable release..."
  $rel = curl.exe -s "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json" | ConvertFrom-Json
  $hash = $rel.current_release.stable
  $entry = $rel.releases | Where-Object { $_.hash -eq $hash -and $_.channel -eq 'stable' } | Select-Object -First 1
  $url = "$($rel.base_url)/$($entry.archive)"
  Log "Downloading Flutter $($entry.version) (~1 GB)..."
  $fz = "$tmp\flutter.zip"
  curl.exe --fail --location --retry 3 --retry-delay 5 -o $fz $url
  Log "Extracting Flutter..."
  tar -xf $fz -C $dev   # zip contains top-level 'flutter\'
  Log "Flutter extracted."
}
$env:PATH = "$flutterDir\bin;$env:PATH"

# ---------- Android command-line tools ----------
$cmdlineLatest = "$sdk\cmdline-tools\latest"
if (Test-Path "$cmdlineLatest\bin\sdkmanager.bat") {
  Log "Android cmdline-tools already present."
} else {
  Log "Downloading Android command-line tools..."
  $cz = "$tmp\cmdline.zip"
  curl.exe --fail --location --retry 3 --retry-delay 5 -o $cz `
    "https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip"
  $cx = "$tmp\cmdline_x"; if (Test-Path $cx) { Remove-Item -Recurse -Force $cx }
  New-Item -ItemType Directory -Force -Path $cx | Out-Null
  tar -xf $cz -C $cx    # zip contains top-level 'cmdline-tools\'
  New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
  if (Test-Path $cmdlineLatest) { Remove-Item -Recurse -Force $cmdlineLatest }
  Move-Item "$cx\cmdline-tools" $cmdlineLatest
  Log "cmdline-tools installed."
}
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk

# ---------- Pre-accept SDK licenses (deterministic, non-interactive) ----------
$licDir = "$sdk\licenses"
New-Item -ItemType Directory -Force -Path $licDir | Out-Null
Set-Content -Path "$licDir\android-sdk-license" -Encoding ascii -NoNewline -Value "`n8933bad161af4178b1185d1a37fbf41ea5269c55`nd56f5187479451eabf01fb78af6dfcb131a6481e`n24333f8a63b6825ea9c5514f83c2829b004d1fee"
Set-Content -Path "$licDir\android-sdk-preview-license" -Encoding ascii -NoNewline -Value "`n84831b9409646a918e30573bab4c9c91346d8abd"
Log "License files written."

# ---------- Persist env vars for future terminals ----------
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkDir, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
$curPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (-not $curPath) { $curPath = '' }
$add = @("$flutterDir\bin", "$jdkDir\bin", "$sdk\cmdline-tools\latest\bin", "$sdk\platform-tools")
foreach ($p in $add) {
  if (($curPath -split ';') -notcontains $p) { $curPath = ($curPath.TrimEnd(';') + ';' + $p) }
}
[Environment]::SetEnvironmentVariable('PATH', $curPath, 'User')
Log "Environment persisted."

Log "DOWNLOAD+EXTRACT STAGE COMPLETE."
Log ("java: " + (& "$jdkDir\bin\java.exe" -version 2>&1 | Select-Object -First 1))
