function Test-KriticalPax8Secrets {
    <#
    .SYNOPSIS
        Preflight gate — verifies Kritical secrets folder + token file are in place
        BEFORE any agent config is touched. Use as the first check in every wrapper.

    .DESCRIPTION
        Read-only. Returns a structured result with `Ok` + per-check details.
        Throws by default when -Strict and any check fails (so callers can use it
        as a guard: `Test-KriticalPax8Secrets -Strict | Out-Null` before mutation).

        Checks performed:
            S1 OneDrive Kritical folder present
            S2 Secrets folder present
            S3 Token file present + non-empty + sane length
            S4 Banner asset present (warning only — falls back to bundled)
            S5 Secrets folder not under any git repo (paranoia check — refuses
               to operate when secrets ended up inside a tracked folder)

    .EXAMPLE
        Test-KriticalPax8Secrets -Strict   # throws on any failure
        Test-KriticalPax8Secrets           # returns object, host-friendly summary

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $SecretsDir,
        [string] $TokenFileName,
        [switch] $Strict,
        [switch] $NoBanner
    )

    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Secrets Preflight' -Compact }

    $secretsDirPath = if ($SecretsDir) { $SecretsDir } else { Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos' }
    $oneDriveRoot   = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd'
    $tokenFile      = if ($TokenFileName) { $TokenFileName } else { 'pax8-mcpServer-auth.txt' }
    $tokenPath      = Join-Path $secretsDirPath $tokenFile
    $bannerPath     = Join-Path $secretsDirPath 'KriticalLogo.txt'

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()
    $add = {
        param($n,$p,$d)
        $checks.Add([pscustomobject]@{ Check=$n; Pass=[bool]$p; Detail=$d })
    }

    # S1
    $s1 = Test-Path -LiteralPath $oneDriveRoot
    & $add 'S1.OneDriveSynced' $s1 $oneDriveRoot

    # S2
    $s2 = Test-Path -LiteralPath $secretsDirPath
    & $add 'S2.SecretsFolder' $s2 $secretsDirPath

    # S3
    $s3 = $false
    $s3detail = ''
    if ($s2 -and (Test-Path -LiteralPath $tokenPath)) {
        try {
            $tok = (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction Stop).Trim()
            if ($tok.Length -ge 16 -and ($tok -notmatch '\s')) {
                $s3 = $true
                $s3detail = "length=$($tok.Length)"
            } else {
                $s3detail = "length=$($tok.Length) — fails sanity"
            }
        } catch {
            $s3detail = "read failed: $($_.Exception.Message)"
        }
    } else {
        $s3detail = "MISSING: $tokenPath"
    }
    & $add 'S3.TokenSane' $s3 $s3detail

    # S4 — warning only
    $s4 = Test-Path -LiteralPath $bannerPath
    $s4Detail = if ($s4) { $bannerPath } else { "not found at $bannerPath (will use bundled fallback)" }
    & $add 'S4.BannerAsset' $s4 $s4Detail

    # S5 — secrets folder must NOT be inside a git repo (catastrophic-leak guard)
    $s5 = $true
    $s5detail = 'OK'
    if ($s2) {
        $probe = $secretsDirPath
        $upwards = @()
        for ($i = 0; $i -lt 10 -and $probe -and $probe.Length -gt 3; $i++) {
            $upwards += $probe
            $gitDir = Join-Path $probe '.git'
            if (Test-Path -LiteralPath $gitDir) {
                $s5 = $false
                $s5detail = "FAIL — secrets folder is inside a git repo at $probe (.git found). Move the secrets folder OUT of any tracked path immediately."
                break
            }
            $probe = Split-Path -Parent $probe
        }
    }
    & $add 'S5.SecretsNotInRepo' $s5 $s5detail

    $failed = @($checks | Where-Object { -not $_.Pass -and $_.Check -ne 'S4.BannerAsset' })
    $ok = ($failed.Count -eq 0)

    if (-not $NoBanner.IsPresent) {
        $checks | Format-Table -AutoSize | Out-String | Write-Host
        if ($ok) {
            Write-Host 'Secrets preflight PASS - safe to proceed.' -ForegroundColor Green
        } else {
            Write-Host ("Secrets preflight FAIL - " + $failed.Count + ' check(s) failed.') -ForegroundColor Red
        }
    }

    $result = [pscustomobject]@{
        Ok            = $ok
        Checks        = @($checks)
        TokenPath     = $tokenPath
        BannerPath    = $bannerPath
        SecretsDir    = $secretsDirPath
        FailedCount   = $failed.Count
    }

    if ($Strict.IsPresent -and -not $ok) {
        throw "Secrets preflight failed ($($failed.Count) of $($checks.Count) checks). Fix and retry; no agent configs touched."
    }

    return $result
}
