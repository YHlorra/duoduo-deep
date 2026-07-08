#!/usr/bin/env pwsh
# Reads .env.local, writes android/key.properties, sets 4 GitHub Actions secrets.
# Re-runnable: any time you change the keystore or password, just edit .env.local
# and run this script again.
#
# Requirements: PowerShell 7+ (`pwsh`) + gh CLI authenticated to YHlorra/duoduo-deep.

$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".." ".env.local"
$envFile = (Resolve-Path $envFile).Path

if (-not (Test-Path $envFile)) {
    Write-Host "::error::$envFile not found. Copy .env.local.example to .env.local and fill in." -ForegroundColor Red
    exit 1
}

# Load .env.local into script-scope variables
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line -match '^\s*#') { return }
    if ($line -match '^\s*(\w+)\s*=\s*(.*?)\s*$') {
        Set-Variable -Name $matches[1] -Value $matches[2] -Scope Script
    }
}

# Validate
$required = @('KEYSTORE_PATH', 'KEY_ALIAS', 'KEYSTORE_PASSWORD', 'KEY_PASSWORD')
foreach ($k in $required) {
    if (-not (Get-Variable -Name $k -Scope Script -ErrorAction SilentlyContinue)) {
        Write-Host "::error::$k missing from $envFile" -ForegroundColor Red
        exit 1
    }
}

# Resolve keystore path relative to repo root
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$keystoreAbs = if ([System.IO.Path]::IsPathRooted($KEYSTORE_PATH)) {
    $KEYSTORE_PATH
} else {
    Join-Path $repoRoot $KEYSTORE_PATH
}
if (-not (Test-Path $keystoreAbs)) {
    Write-Host "::error::Keystore not found at $keystoreAbs" -ForegroundColor Red
    exit 1
}

# Write android/key.properties (relative path, as required by build.gradle.kts)
$keyPropsRel = $KEYSTORE_PATH
$keyProps = @"
storeFile=$keyPropsRel
storePassword=$KEYSTORE_PASSWORD
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASSWORD
"@
$keyPropsPath = Join-Path $repoRoot "android/key.properties"
Set-Content -Path $keyPropsPath -Value $keyProps -NoNewline
Write-Host "[ok] Wrote android/key.properties" -ForegroundColor Green

# Set 4 GitHub Actions secrets
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystoreAbs))
gh secret set KEYSTORE_BASE64 --repo YHlorra/duoduo-deep --body $base64        | Out-Null
gh secret set KEYSTORE_PASSWORD --repo YHlorra/duoduo-deep --body $KEYSTORE_PASSWORD | Out-Null
gh secret set KEY_ALIAS --repo YHlorra/duoduo-deep --body $KEY_ALIAS             | Out-Null
gh secret set KEY_PASSWORD --repo YHlorra/duoduo-deep --body $KEY_PASSWORD       | Out-Null
Write-Host "[ok] Set 4 GitHub secrets: KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD" -ForegroundColor Green

# Verify
Write-Host ""
Write-Host "Current GitHub secrets on YHlorra/duoduo-deep:" -ForegroundColor Cyan
gh secret list --repo YHlorra/duoduo-deep | Select-String -Pattern "KEYSTORE|KEY_ALIAS|KEY_PASSWORD"
