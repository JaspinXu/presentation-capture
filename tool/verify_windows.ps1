param(
    [string]$Flutter = 'G:\flutter-sdk\bin\flutter.bat',
    [switch]$BuildApk
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $Flutter)) {
    throw "Flutter was not found at $Flutter. Install it or pass -Flutter <path-to-flutter.bat>."
}

Push-Location $projectRoot
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    & $Flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    & $Flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
    if ($BuildApk) {
        & $Flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed' }
    }

    Push-Location (Join-Path $projectRoot 'server')
    try {
        npm test
        if ($LASTEXITCODE -ne 0) { throw 'server tests failed' }
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            docker compose config --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid' }
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}

Write-Host 'All requested Windows checks passed.' -ForegroundColor Green
