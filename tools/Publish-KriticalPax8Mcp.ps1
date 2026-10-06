<#
.SYNOPSIS
    Publish Kritical.PS.Pax8Mcp to PSGallery via the canonical Kritical secrets pattern.
    Stages to a properly-named folder, reads API key from secrets folder, validates
    manifest, dry-runs via Test-ModuleManifest, then publishes.

.DESCRIPTION
    PSGallery's Publish-Module requires the containing folder to share the module
    name. Our repo has src\Kritical.PS.Pax8Mcp.psd1 (folder=src). This helper:

      1. Confirms the API key file exists in the Kritical secrets folder.
      2. Stages the module into %LOCALAPPDATA%\Kritical\Kritical.PS.Pax8Mcp\publish-staging\Kritical.PS.Pax8Mcp\
         (out of any repo).
      3. Validates the staged manifest.
      4. Reads the API key into a local var (never echoed).
      5. Push-Location to staging parent, runs Publish-Module with fully-qualified path.
      6. Pop-Location regardless of outcome.
      7. Returns a structured result.

    Idempotent. Re-runnable. Safe to re-stage.

.PARAMETER ApiKeyFile
    Default: $env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\psgallery-api-key.txt

.PARAMETER WhatIf
    Standard. Skips the actual Publish-Module call; everything else runs.

.NOTES
    Author: Joshua Finley - Kritical Pty Ltd
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [string] $ApiKeyFile,
    [string] $ModuleName = 'Kritical.PS.Pax8Mcp',
    [string] $RepoRoot,
    [switch] $SkipManifestTest,
    [switch] $SkipTests,         # default: run full Pester unit + e2e suite before publish
    [switch] $SkipDocCheck,      # default: verify README/LICENSE/CONTRIBUTING/docs/*.md present + banner-embedded
    [switch] $SkipE2E,           # forwarded to Invoke-AllTests
    [switch] $NoBanner
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve fully-qualified paths up-front; never use relative ones
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$srcDir   = Join-Path $RepoRoot 'src'
if (-not (Test-Path -LiteralPath $srcDir)) { throw "src folder not found at $srcDir" }

if (-not $ApiKeyFile) {
    $ApiKeyFile = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\psgallery-api-key.txt'
}

# Banner (from canonical secrets-folder logo, fallback to bundled)
if (-not $NoBanner.IsPresent) {
    $logo = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\KriticalLogo.txt'
    if (-not (Test-Path -LiteralPath $logo)) { $logo = Join-Path $srcDir 'Assets\kritical-logo.txt' }
    if (Test-Path -LiteralPath $logo) {
        Write-Host (Get-Content -LiteralPath $logo -Raw) -ForegroundColor DarkCyan
        Write-Host '--- Publish Kritical.PS.Pax8Mcp to PSGallery ---' -ForegroundColor Yellow
    }
}

# 1. API key file present + non-empty
if (-not (Test-Path -LiteralPath $ApiKeyFile)) {
    throw "PSGallery API key file not found at $ApiKeyFile. Mint at https://www.powershellgallery.com/account/apikeys then save to that path."
}
$apiKey = (Get-Content -LiteralPath $ApiKeyFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "API key file is empty: $ApiKeyFile" }
if ($apiKey.Length -lt 30) { throw "API key suspiciously short ($($apiKey.Length) chars) at $ApiKeyFile" }
Write-Host ("API key loaded (length=" + $apiKey.Length + " chars; first-4 masked).") -ForegroundColor Green

# 1b. Doc-readiness gate (refuse to publish without the canonical docs)
if (-not $SkipDocCheck.IsPresent) {
    Write-Host 'Validating documentation set...' -ForegroundColor DarkCyan
    $required = @{
        'README.md'             = 'Top-level README'
        'LICENSE'               = 'License file'
        'CONTRIBUTING.md'       = 'Contributing guide'
        'docs\USAGE.md'         = 'Usage guide'
        'docs\ARCHITECTURE.md'  = 'Architecture overview'
        'docs\PUBLISHING.md'    = 'Publishing runbook'
    }
    $docFailures = @()
    foreach ($rel in $required.Keys) {
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            $docFailures += "MISSING: $rel ($($required[$rel]))"
            continue
        }
        $content = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
        # Banner-embed gate (skip the LICENSE which legitimately has no banner)
        if ($rel -ne 'LICENSE' -and $content -and ($content -notmatch 'SirJ|Kritical' )) {
            $docFailures += "NO-KRITICAL-BRAND: $rel does not reference SirJ/Kritical"
        }
        # Author-stamp gate
        if ($rel -in @('LICENSE','CONTRIBUTING.md','docs\ARCHITECTURE.md','docs\PUBLISHING.md','docs\USAGE.md','README.md') -and $content -and ($content -notmatch 'Joshua Finley')) {
            $docFailures += "NO-AUTHOR-STAMP: $rel does not mention Joshua Finley"
        }
    }
    if ($docFailures.Count -gt 0) {
        $docFailures | ForEach-Object { Write-Host ("  [FAIL] $_") -ForegroundColor Red }
        throw "Doc readiness FAILED ($($docFailures.Count) issue(s)). Use -SkipDocCheck to override (not recommended)."
    }
    Write-Host ("  All " + $required.Count + ' docs present + branded + authored.') -ForegroundColor Green
}

# 1c. Full test suite gate (Pester unit + e2e) — refuse to publish on red
# Isolate -WhatIf so it doesn't bleed into the test runner's file operations.
if (-not $SkipTests.IsPresent) {
    Write-Host 'Running full test suite before publish...' -ForegroundColor DarkCyan
    $runner = Join-Path $RepoRoot 'tests\Invoke-AllTests.ps1'
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Test runner not found at $runner. Use -SkipTests to override (not recommended)."
    }
    $testArgs = @{ NoBanner = $true }
    if ($SkipE2E.IsPresent) { $testArgs.SkipE2E = $true }
    $savedWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    try {
        & $runner @testArgs
    } finally {
        $WhatIfPreference = $savedWhatIf
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Test suite FAILED (exit $LASTEXITCODE). Refusing to publish a red build. Use -SkipTests to override (NOT recommended)."
    }
    Write-Host '  Test suite GREEN.' -ForegroundColor Green
}

# 2. Stage into properly-named folder
$stagingBase = Join-Path $env:LOCALAPPDATA "Kritical\$ModuleName\publish-staging"
$stagingMod  = Join-Path $stagingBase $ModuleName
if (Test-Path -LiteralPath $stagingMod) {
    Remove-Item -LiteralPath $stagingMod -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingMod -Force | Out-Null
Copy-Item -Recurse -Force "$srcDir\*" $stagingMod
Write-Host ("Staged module -> " + $stagingMod) -ForegroundColor Green

# 3. Validate the staged manifest
$stagedPsd1 = Join-Path $stagingMod "$ModuleName.psd1"
if (-not (Test-Path -LiteralPath $stagedPsd1)) { throw "Manifest not found at $stagedPsd1 after stage" }
if (-not $SkipManifestTest.IsPresent) {
    Write-Host 'Validating manifest...' -ForegroundColor DarkCyan
    $mi = Test-ModuleManifest -Path $stagedPsd1
    Write-Host ("  Name:    " + $mi.Name)
    Write-Host ("  Version: " + $mi.Version)
    Write-Host ("  Author:  " + $mi.Author)
    Write-Host ("  Company: " + $mi.CompanyName)
    Write-Host ("  Exported functions: " + ($mi.ExportedFunctions.Keys -join ', '))
    if ($mi.Author -ne 'Joshua Finley') { Write-Warning "Author is '$($mi.Author)' (expected 'Joshua Finley')" }
    if ($mi.CompanyName -ne 'Kritical Pty Ltd') { Write-Warning "Company is '$($mi.CompanyName)' (expected 'Kritical Pty Ltd')" }
}

# 4. Push-Location to the staging PARENT, publish using fully-qualified path
$pushedTo = $stagingBase
Write-Host ("Push-Location -> " + $pushedTo) -ForegroundColor DarkGray
Push-Location -LiteralPath $pushedTo
try {
    if ($PSCmdlet.ShouldProcess($stagingMod, "Publish-Module to PSGallery")) {
        Write-Host 'Calling Publish-Module...' -ForegroundColor DarkCyan
        Publish-Module -Path $stagingMod -NuGetApiKey $apiKey -Verbose -ErrorAction Stop
        $published = $true
        Write-Host ("Published OK -> " + "https://www.powershellgallery.com/packages/$ModuleName") -ForegroundColor Green
    } else {
        Write-Host '-WhatIf — skipping actual Publish-Module call.' -ForegroundColor Yellow
        $published = $false
    }
} finally {
    Pop-Location
}

[pscustomobject]@{
    Module       = $ModuleName
    Source       = $srcDir
    StagedAt     = $stagingMod
    Published    = $published
    PSGalleryUrl = "https://www.powershellgallery.com/packages/$ModuleName"
    ApiKeyFile   = $ApiKeyFile
}
