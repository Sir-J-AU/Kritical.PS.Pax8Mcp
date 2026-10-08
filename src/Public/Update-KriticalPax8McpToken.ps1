function Update-KriticalPax8McpToken {
    <#
    .SYNOPSIS
        Rotate the Pax8 MCP token: prompt for the new value (SecureString, no echo),
        back up the old token, write the new one to the secrets folder, re-wire every
        currently-wired agent, re-probe live.

    .DESCRIPTION
        Use after the operator mints a new token from app.pax8.com (Settings >
        Integrations > MCP server > Connect > Claude > Option 2 Pax8 Token).

        Token is read via Read-Host -AsSecureString so it never appears in the
        host buffer / transcript / clipboard echo.

    .EXAMPLE
        Update-KriticalPax8McpToken
        Prompts; rotates; re-wires every detected agent.

    .EXAMPLE
        Update-KriticalPax8McpToken -NewToken (Get-Content C:\drop\new-token.txt -Raw)
        Non-interactive rotation (CI / Hermes / supervisor).

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string] $NewToken,
        [string] $SecretsDir,
        [string] $TokenFileName,
        [string[]] $Agent,
        [switch] $NoBanner,
        [switch] $SkipReinstall
    )
    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Rotate Pax8 MCP Token' }

    $tokenPath = Get-KriticalPax8TokenPath -SecretsDir $SecretsDir -TokenFileName $TokenFileName

    if (-not $NewToken) {
        Write-Host ''
        Write-Host 'Mint a fresh Pax8 MCP token via:' -ForegroundColor Yellow
        Write-Host '  https://app.pax8.com -> Settings -> Integrations -> MCP server -> Connect -> Claude -> Option 2 Pax8 Token'
        $sec = Read-Host 'Paste new Pax8 MCP token (input not echoed)' -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $NewToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
        }
    }
    $NewToken = $NewToken.Trim()
    if ([string]::IsNullOrWhiteSpace($NewToken)) { throw 'No token entered.' }
    if (-not (Test-KriticalPax8TokenSane -Token $NewToken)) {
        throw ("New token rejected — failed sanity check (length=$($NewToken.Length), whitespace=" + ($NewToken -match '\s') + ").")
    }

    # Backup existing token
    $bak = $null
    if (Test-Path -LiteralPath $tokenPath) {
        $utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
        $bak = "$tokenPath.bak.$utc"
        if ($PSCmdlet.ShouldProcess($tokenPath, "Back up existing token to $bak")) {
            Move-Item -LiteralPath $tokenPath -Destination $bak -Force
        }
    }
    if ($PSCmdlet.ShouldProcess($tokenPath, 'Write new token')) {
        [System.IO.File]::WriteAllText($tokenPath, $NewToken, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host ('Token written to: ' + $tokenPath) -ForegroundColor Green

    $installResult = $null
    if (-not $SkipReinstall.IsPresent) {
        Write-Host 'Re-wiring agents with new token...' -ForegroundColor DarkCyan
        $installResult = Install-KriticalPax8Mcp -Agent $Agent -SecretsDir $SecretsDir -TokenFileName $TokenFileName -NoBanner -SkipProbe
    }

    Write-Host 'Probing mcp.pax8.com with new token...' -ForegroundColor DarkCyan
    $probe = Invoke-KriticalPax8McpInitialize -Token $NewToken
    if ($probe.Ok) {
        $tools = Get-KriticalPax8McpToolList -Token $NewToken
        Write-Host ("  Server: " + $probe.ServerName + " v" + $probe.ServerVersion + " | tools: " + $tools.ToolCount) -ForegroundColor Green
    } else {
        Write-Host ('  [FAIL] ' + ($probe.Error ?? "HTTP $($probe.StatusCode)")) -ForegroundColor Red
    }

    [pscustomobject]@{
        TokenPath       = $tokenPath
        Backup          = $bak
        ProbeOk         = $probe.Ok
        ProbeServer     = $probe.ServerName
        InstallResult   = $installResult
        RestartRequired = $true
    }
}
