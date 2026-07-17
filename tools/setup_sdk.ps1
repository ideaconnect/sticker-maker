# Stage 2: install Android SDK packages, wire Flutter to the SDK/JDK, run flutter doctor.
# Run AFTER install_tools.ps1. Idempotent; no admin required.
# NOTE: ErrorActionPreference is 'Continue' on purpose — sdkmanager/flutter write progress to
# stderr, and under 'Stop' PowerShell 5.1 would treat that as a terminating error. We check
# $LASTEXITCODE explicitly where it matters instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$dev = "$env:USERPROFILE\dev"
$jdkDir = "$dev\jdk-17"
$flutterDir = "$dev\flutter"
$sdk = "$dev\android-sdk"

$env:JAVA_HOME = $jdkDir
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk
$env:PATH = "$flutterDir\bin;$jdkDir\bin;$sdk\cmdline-tools\latest\bin;$sdk\platform-tools;$env:PATH"

function Log($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"

Log "Accepting SDK licenses..."
$y = (("y`r`n") * 60)
$y | & $sdkmanager --sdk_root=$sdk --licenses | Out-Null

Log "Installing platform-tools, platforms;android-36, build-tools;36.0.0 ..."
& $sdkmanager --sdk_root=$sdk "platform-tools" "platforms;android-36" "build-tools;36.0.0"
if ($LASTEXITCODE -ne 0) { Log "WARNING: sdkmanager exited $LASTEXITCODE" }

Log "Configuring Flutter..."
& "$flutterDir\bin\flutter.bat" config --no-analytics | Out-Null
& "$flutterDir\bin\flutter.bat" config --android-sdk $sdk --jdk-dir $jdkDir | Out-Null

Log "flutter --version:"
& "$flutterDir\bin\flutter.bat" --version

Log "flutter doctor -v:"
& "$flutterDir\bin\flutter.bat" doctor -v

Log "SETUP_SDK STAGE COMPLETE."
