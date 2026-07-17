# Run the end-to-end (integration_test) suite on a headless Android emulator.
#
# Boots the `sm_test` AVD (creating it if missing), waits for boot to complete,
# then drives the real app on-device via `flutter test integration_test/`.
# Idempotent and self-contained; no admin required. Assumes the toolchain from
# tools/install_tools.ps1 + tools/setup_sdk.ps1 lives in %USERPROFILE%\dev.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_e2e.ps1
#   ... -KeepEmulator        # leave the emulator running afterwards
#
# The emulator runs with the software (SwiftShader) GPU so it works headlessly
# on CI. The app's debug build disables Impeller (see
# android/app/src/debug/AndroidManifest.xml) so the Skia renderer is used, which
# is stable on SwiftShader — Impeller/Vulkan crashes the software emulator.

param(
  [switch]$KeepEmulator,
  [string]$AvdName = 'sm_test',
  [string]$SystemImage = 'system-images;android-35;google_apis;x86_64',
  [string]$Device = 'pixel_6'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$dev = "$env:USERPROFILE\dev"
$sdk = "$dev\android-sdk"
$env:JAVA_HOME = "$dev\jdk-17"
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk
$env:PATH = "$dev\flutter\bin;$dev\jdk-17\bin;$sdk\cmdline-tools\latest\bin;$sdk\platform-tools;$sdk\emulator;$env:PATH"

$adb = "$sdk\platform-tools\adb.exe"
$emulator = "$sdk\emulator\emulator.exe"
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
$avdmanager = "$sdk\cmdline-tools\latest\bin\avdmanager.bat"

function Log($m) { Write-Host ("[e2e] {0}" -f $m) }

# 1. Ensure the emulator binary + system image are installed.
if (-not (Test-Path $emulator)) {
  Log "Installing emulator + system image ($SystemImage) ..."
  ((("y`r`n") * 60)) | & $sdkmanager --sdk_root=$sdk --licenses | Out-Null
  & $sdkmanager --sdk_root=$sdk "emulator" "platform-tools" $SystemImage
}

# 2. Ensure the AVD exists.
$haveAvd = (& $avdmanager list avd 2>&1 | Select-String -SimpleMatch "Name: $AvdName")
if (-not $haveAvd) {
  Log "Creating AVD '$AvdName' ..."
  "no" | & $avdmanager create avd -n $AvdName -k $SystemImage -d $Device --force
}

# 3. Boot the emulator headless unless one is already attached.
$alreadyUp = (& $adb devices | Select-String -Pattern "emulator-\d+\s+device")
if (-not $alreadyUp) {
  Log "Booting emulator '$AvdName' (headless, SwiftShader GPU) ..."
  Start-Process -FilePath $emulator `
    -ArgumentList @('-avd', $AvdName, '-no-window', '-no-audio', '-no-boot-anim', '-no-snapshot', '-gpu', 'swiftshader_indirect', '-accel', 'on') `
    -WindowStyle Hidden
  & $adb start-server | Out-Null
  & $adb wait-for-device
  Log "Waiting for boot to complete ..."
  $booted = $false
  for ($i = 0; $i -lt 90; $i++) {
    if ((& $adb shell getprop sys.boot_completed 2>$null) -match '1') { $booted = $true; break }
    Start-Sleep -Seconds 2
  }
  if (-not $booted) { Log "ERROR: emulator did not finish booting"; exit 1 }
  Log "Emulator booted."
}

$deviceId = ((& $adb devices | Select-String -Pattern "(emulator-\d+)\s+device").Matches[0].Groups[1].Value)
Log "Running integration tests on $deviceId ..."
& flutter test integration_test 2>&1 | Write-Host
$code = $LASTEXITCODE
Log "flutter test exit code: $code"

if (-not $KeepEmulator) {
  Log "Shutting down emulator ..."
  & $adb -s $deviceId emu kill 2>$null | Out-Null
}

exit $code
