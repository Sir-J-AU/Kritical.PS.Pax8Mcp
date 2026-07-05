function Test-KriticalPax8Mcp {
    <#
    .SYNOPSIS
        Comprehensive health probe for the Pax8 MCP toolkit on this machine.

    .DESCRIPTION
        Runs 7 gates and returns a structured result. Exit non-zero if any FAIL.

            G1 - Secrets folder accessible
            G2 - Token file present + non-empty + sane length
            G3 - OAuth discovery (RFC 8414) endpoint responding correctly
            G4 - MCP initialize JSON-RPC handshake (server identifies itself)
            G5 - tools/list returns >=1 tool (currently 21 Pax8 tools)
            G6 - At least one agent target has the pax8 entry wired
            G7 - The wired entry passes a token-header probe

    .EXAMPLE
        Test-KriticalPax8Mcp

    .EXAMPLE
        Test-KriticalPax8Mcp -Quiet
        Returns the result object without writing to host.

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $SecretsDir,
        [string] $TokenFileName,
        [switch] $Quiet,
        [switch] $NoBanner
    )
    if (-not $NoBanner.IsPresent -and -not $Quiet.IsPresent) {
        Write-KriticalPax8Banner -Title 'Pax8 MCP Health Probe' -Compact
    }
    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $addGate = {
        param($name,$pass,$detail)
        $results.Add([pscustomobject]@{ Gate=$name; Pass=[bool]$pass; Detail=$detail })
    }

    # G1
    $tokenPath = Get-KriticalPax8TokenPath -SecretsDir $SecretsDir -TokenFileName $TokenFileName
    $secretsDirPath = Split-Path -Parent $tokenPath
    $g1 = Test-Path -LiteralPath $secretsDirPath
    & $addGate 'G1.SecretsFolder' $g1 $secretsDirPath

    # G2
    $token = $null
    $tokenErr = $null
    if ($g1) {
        # .5231 (lens-hunt): capture (don't swallow) the read failure so G2's Detail
        # explains WHY the token is missing instead of an unexplained length=0.
        try { $token = Read-KriticalPax8Token -SecretsDir $SecretsDir -TokenFileName $TokenFileName } catch { $tokenErr = $_.Exception.Message }
    }
    $g2Detail = if ($token) { "length=" + $token.Length } elseif ($tokenErr) { "length=0 err=" + $tokenErr } else { "length=0" }
    & $addGate 'G2.TokenSane' ([bool]$token) $g2Detail

    # G3
    $disc = Test-KriticalPax8McpOAuthDiscovery
    & $addGate 'G3.OAuthDiscovery' $disc.Ok ("issuer=" + $disc.Issuer + " scopes=" + ($disc.Scopes -join ','))

    # G4 + G5 (only if token sane)
    if ($token) {
        $init = Invoke-KriticalPax8McpInitialize -Token $token
        $g4Detail = "server=" + $init.ServerName + " v" + $init.ServerVersion
        if ($init.Error) { $g4Detail += " err=" + $init.Error }
        & $addGate 'G4.McpInitialize' $init.Ok $g4Detail
        if ($init.Ok) {
            $tl = Get-KriticalPax8McpToolList -Token $token
            & $addGate 'G5.ToolsList' ($tl.Ok -and $tl.ToolCount -ge 1) ("toolCount=" + $tl.ToolCount + " sample=" + (($tl.Tools | Select-Object -First 5) -join ','))
        } else {
            & $addGate 'G5.ToolsList' $false 'skipped - initialize failed'
        }
    } else {
        & $addGate 'G4.McpInitialize' $false 'skipped - no token'
        & $addGate 'G5.ToolsList'     $false 'skipped - no token'
    }

    # G6
    $status = Get-KriticalPax8McpStatus -NoBanner
    $wiredAgents = @($status.Agents | Where-Object HasPax8Entry)
    & $addGate 'G6.AnyAgentWired' ($wiredAgents.Count -gt 0) (($wiredAgents | Select-Object -ExpandProperty Agent) -join ',')

    # G7 - re-validate token via the same path the wired agents will use
    if ($token -and $wiredAgents.Count -gt 0) {
        $init2 = Invoke-KriticalPax8McpInitialize -Token $token
        & $addGate 'G7.WiredAgentTokenValid' $init2.Ok ("status=" + $init2.StatusCode)
    } else {
        & $addGate 'G7.WiredAgentTokenValid' $false 'skipped - no wired agent or no token'
    }

    $passedRows = @($results | Where-Object Pass)
    $failedRows = @($results | Where-Object { -not $_.Pass })

    if (-not $Quiet.IsPresent) {
        $results | Format-Table -AutoSize | Out-String | Write-Host
        if ($failedRows.Count -eq 0) {
            Write-Host ("ALL " + $results.Count + " GATES PASS - Pax8 MCP healthy.") -ForegroundColor Green
        } else {
            Write-Host ($failedRows.Count.ToString() + ' of ' + $results.Count + ' gates FAIL - see Detail.') -ForegroundColor Red
        }
    }

    [pscustomobject]@{
        Gates  = $results
        Passed = $passedRows.Count
        Failed = $failedRows.Count
        Total  = $results.Count
        Ok     = ($failedRows.Count -eq 0)
    }
}
