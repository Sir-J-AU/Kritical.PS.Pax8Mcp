function Remove-KriticalPax8Mcp {
    <#
    .SYNOPSIS
        Removes the Pax8 MCP wiring from one or more agents on this machine.
        Token file in the secrets folder is preserved unless -RemoveToken is passed.

    .DESCRIPTION
        Idempotent. Backs up each agent config before removal. Leaves all other
        MCP entries (falcon-mcp, etc.) untouched.

    .EXAMPLE
        Remove-KriticalPax8Mcp -Agent claude
        Removes pax8 + pax8-oauth entries from Claude Code only.

    .EXAMPLE
        Remove-KriticalPax8Mcp
        Removes from every currently-wired agent.

    .EXAMPLE
        Remove-KriticalPax8Mcp -RemoveToken
        Also moves the token file aside (kept as .bak.<utc>) so a fresh mint is required.

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Agent,
        [switch]   $RemoveToken,
        [string]   $SecretsDir,
        [string]   $TokenFileName,
        [switch]   $NoBanner
    )
    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Remove Pax8 MCP' }

    $allTargets = Get-KriticalPax8AgentTargets
    $selection = if ($Agent) {
        $allTargets | Where-Object Name -in $Agent
    } else {
        # only remove from agents that have the entry — minimize churn
        $status = Get-KriticalPax8McpStatus -NoBanner
        $wired = $status.Agents | Where-Object HasPax8Entry | Select-Object -ExpandProperty Agent
        $allTargets | Where-Object Name -in $wired
    }

    if (-not $selection) {
        Write-Host 'No wired agents found. Nothing to remove.' -ForegroundColor Yellow
        return
    }

    $tokenForRewriting = $null
    try { $tokenForRewriting = Read-KriticalPax8Token -SecretsDir $SecretsDir -TokenFileName $TokenFileName -AllowMissing } catch { }
    if (-not $tokenForRewriting) { $tokenForRewriting = 'TOKEN-NOT-AVAILABLE' }

    $rows = @()
    foreach ($t in $selection) {
        if ($PSCmdlet.ShouldProcess($t.Path, "Remove pax8 + pax8-oauth entries")) {
            try {
                $res = Install-KriticalPax8McpForAgent -AgentName $t.Name -Token $tokenForRewriting -RemoveOnly
                $rows += [pscustomobject]@{ Agent=$t.Name; Path=$t.Path; Ok=$true; Backup=$res.Backup }
                Write-Host ("  [OK] removed from " + $t.Name) -ForegroundColor Green
            } catch {
                $rows += [pscustomobject]@{ Agent=$t.Name; Path=$t.Path; Ok=$false; Detail=$_.Exception.Message }
                Write-Host ("  [FAIL] " + $t.Name + " -> " + $_.Exception.Message) -ForegroundColor Red
            }
        }
    }

    $tokenRemoved = $false
    if ($RemoveToken.IsPresent) {
        $tokenPath = Get-KriticalPax8TokenPath -SecretsDir $SecretsDir -TokenFileName $TokenFileName
        if (Test-Path -LiteralPath $tokenPath) {
            $utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
            $bak = "$tokenPath.bak.removed.$utc"
            if ($PSCmdlet.ShouldProcess($tokenPath, "Move token to $bak")) {
                Move-Item -LiteralPath $tokenPath -Destination $bak -Force
                $tokenRemoved = $true
                Write-Host ("Token moved aside to: " + $bak) -ForegroundColor Yellow
            }
        }
    }

    [pscustomobject]@{
        Agents       = $rows
        TokenRemoved = $tokenRemoved
        Restart      = $true
    }
}
