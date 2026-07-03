<#
.SYNOPSIS
    Kritical.Pax8Mcp full test runner. Runs Pester 5+ unit tests then live e2e
    against mcp.pax8.com (skipped if secrets folder absent).

.DESCRIPTION
    Output goes to tests/output/last-run-<utc>.{xml,txt}. Exit non-zero on any failure.

.AUTHOR
    Joshua Finley - Kritical Pty Ltd
#>
[CmdletBinding()]
param(
    [switch] $SkipE2E,
    [switch] $NoBanner,
    [string] $OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
$repo = Split-Path -Parent $here
Import-Module (Join-Path $repo 'src\Kritical.Pax8Mcp.psd1') -Force

if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Test Runner' }

# Ensure Pester 5
$pester = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    Write-Host 'Installing Pester 5...' -ForegroundColor Yellow
    Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
}
Import-Module Pester -MinimumVersion 5.5.0 -Force

# Default test output OUT of the repo so artefacts never accidentally commit.
# Override with -OutputDir for CI / explicit collection.
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:LOCALAPPDATA 'Kritical\Kritical.Pax8Mcp\test-output'
}
$outDir = $OutputDir
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Host ("Test artefacts -> " + $outDir) -ForegroundColor DarkGray
$utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')

$paths = @((Join-Path $here 'Unit'))
if (-not $SkipE2E.IsPresent) {
    $paths = @((Join-Path $here 'Unit'), (Join-Path $here 'E2E'))
}
$conf = New-PesterConfiguration
$conf.Run.Path = $paths
$conf.Output.Verbosity = 'Detailed'
$conf.TestResult.Enabled = $true
$conf.TestResult.OutputPath = (Join-Path $outDir "results-$utc.xml")
$conf.TestResult.OutputFormat = 'NUnitXml'
$conf.Run.PassThru = $true

$result = Invoke-Pester -Configuration $conf

# Summary
$summary = [pscustomobject]@{
    UtcStamp        = $utc
    TotalTests      = $result.TotalCount
    PassedCount     = $result.PassedCount
    FailedCount     = $result.FailedCount
    SkippedCount    = $result.SkippedCount
    NotRunCount     = $result.NotRunCount
    Duration        = $result.Duration
    Result          = $result.Result
    XmlReportPath   = $conf.TestResult.OutputPath.Value
}
$summary | Format-List | Out-String | Write-Host

$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outDir "summary-$utc.json")

if ($result.Result -ne 'Passed') {
    Write-Host ("FAIL — " + $result.FailedCount + ' test(s) failed.') -ForegroundColor Red
    exit 1
}
Write-Host ("PASS — " + $result.PassedCount + ' tests; ' + $result.SkippedCount + ' skipped; ' + $result.Duration + ' total.') -ForegroundColor Green
exit 0
