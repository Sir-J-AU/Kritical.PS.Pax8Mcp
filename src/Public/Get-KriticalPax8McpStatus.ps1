function Get-KriticalPax8McpStatus {
    <#
    .SYNOPSIS
        Reports the current Pax8 MCP wiring state across every supported agent on this machine.

    .DESCRIPTION
        Read-only. For each agent target, reports whether the host is installed,
        whether `pax8` and `pax8-oauth` entries are present, and whether the
        token-auth header is configured.

    .EXAMPLE
        Get-KriticalPax8McpStatus | Format-Table -AutoSize

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [switch] $NoBanner
    )
    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Pax8 MCP Status' -Compact }
    $tokenPath = Get-KriticalPax8TokenPath
    $tokenPresent = Test-Path -LiteralPath $tokenPath
    $rows = @()
    foreach ($t in (Get-KriticalPax8AgentTargets)) {
        $entryPax8 = $false; $entryOAuth = $false; $hasTokenHeader = $false
        if ($t.ConfigExists) {
            $raw = Get-Content -LiteralPath $t.Path -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                if ($t.Format -eq 'json') {
                    $entryPax8     = ($raw -match '"pax8"\s*:\s*\{')
                    $entryOAuth    = ($raw -match '"pax8-oauth"\s*:\s*\{')
                    $hasTokenHeader = ($raw -match '"x-pax8-mcp-token"\s*:\s*"[^"]+')
                } elseif ($t.Format -eq 'toml') {
                    $entryPax8     = ($raw -match '(?m)^\[mcp_servers\.pax8\]')
                    $entryOAuth    = $false  # codex uses single OAuth-shape entry
                    $hasTokenHeader = $false # codex shape doesn't embed token
                }
            }
        }
        $rows += [pscustomobject]@{
            Agent           = $t.Name
            HostInstalled   = $t.HostInstalled
            ConfigPath      = $t.Path
            ConfigExists    = $t.ConfigExists
            HasPax8Entry    = $entryPax8
            HasOAuthEntry   = $entryOAuth
            HasTokenHeader  = $hasTokenHeader
        }
    }
    [pscustomobject]@{
        TokenPath     = $tokenPath
        TokenPresent  = $tokenPresent
        Agents        = $rows
    }
}
