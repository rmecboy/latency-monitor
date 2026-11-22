$ErrorActionPreference = "Stop"

$toolsRoot = "D:\dsh_ws\BlueSpeaker\tools"
$env:JAVA_HOME = Join-Path $toolsRoot "java\jdk-17.0.20.1+1"
$env:ANDROID_HOME = Join-Path $toolsRoot "android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$gradleBat = Join-Path $toolsRoot "gradle-8.9\bin\gradle.bat"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$androidDir = Join-Path $root "android"
$releaseDir = Join-Path $root "release"

if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

Write-Host "Using JAVA_HOME:    $env:JAVA_HOME" -ForegroundColor Cyan
Write-Host "Using ANDROID_HOME: $env:ANDROID_HOME" -ForegroundColor Cyan

Push-Location $androidDir
try {
    & $gradleBat assembleRelease --offline --no-daemon
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Offline build failed, retrying online..." -ForegroundColor Yellow
        & $gradleBat assembleRelease --no-daemon
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle build failed with exit code $LASTEXITCODE"
        }
    }
} finally {
    Pop-Location
}

$apkSrc = Join-Path $androidDir "app\build\outputs\apk\release\app-release.apk"
$apkDst = Join-Path $releaseDir "LatencyMonitor.apk"
Copy-Item $apkSrc $apkDst -Force

$info = Get-Item $apkDst
Write-Host "Build succeeded: $($info.FullName) ($($info.Length) bytes)" -ForegroundColor Green
