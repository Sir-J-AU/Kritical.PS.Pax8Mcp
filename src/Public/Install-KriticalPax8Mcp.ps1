function Install-KriticalPax8Mcp {
    <#
    .SYNOPSIS
        Installs the Pax8 hosted MCP server into one or more agents on this machine.
        Token-auth path is primary; OAuth DCR entry can be added as a secondary entry.

    .DESCRIPTION
        Idempotent installer. For each agent target the operator specifies, the
        function:
          1. Reads the Pax8 MCP token from the Kritical secrets folder.
          2. Backs up the target agent config to .bak.krit-pax8mcp.<utc>.
          3. Writes the appropriate config block (JSON or TOML per agent shape).
          4. Probes mcp.pax8.com with the token and reports tool count.
          5. Emits the Kritical banner + a clear restart instruction for the agent.

        Supported agents (auto-detected; only writes to existing host config dirs unless -Force):
          - claude          (Claude Code, ~/.claude.json, JSON, mcpServers)
          - codex           (Codex CLI, ~/.codex/config.toml, TOML)
          - cursor          (Cursor IDE, ~/.cursor/mcp.json, JSON)
          - continue        (Continue.dev, ~/.continue/config.json, JSON)
          - vscode          (VS Code stable, %APPDATA%\Code\User\mcp.json)
          - vscode-insiders (VS Code Insiders, %APPDATA%\Code - Insiders\User\mcp.json)

    .PARAMETER Agent
        One or more agent names to wire. Default: all detected.

    .PARAMETER SecretsDir
        Kritical secrets folder. Default: $env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos

    .PARAMETER TokenFileName
        Token file name in SecretsDir. Default: pax8-mcpServer-auth.txt

    .PARAMETER IncludeOAuthEntry
        Add a secondary "pax8-oauth" entry that triggers OAuth Dynamic Client Registration + browser MFA on first use. Default: included.

    .PARAMETER Force
        Wire even if the host agent isn't detected installed (parent dir absent). Creates the path.

    .PARAMETER SkipProbe
        Skip the live mcp.pax8.com probe.

    .EXAMPLE
        Install-KriticalPax8Mcp -Agent claude
        Wires Claude Code only.

    .EXAMPLE
        Install-KriticalPax8Mcp
        Auto-detects and wires every installed agent.

    .EXAMPLE
        Install-KriticalPax8Mcp -Agent claude,cursor -IncludeOAuthEntry:$false
        Wires Claude + Cursor with the token entry only (no OAuth secondary).

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
        See also: Get-KriticalPax8McpStatus, Test-KriticalPax8Mcp, Update-KriticalPax8McpToken, Remove-KriticalPax8Mcp
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Agent,
        [string]   $SecretsDir,
        [string]   $TokenFileName,
        [switch]   $IncludeOAuthEntry = $true,
        [switch]   $Force,
        [switch]   $SkipProbe,
        [switch]   $NoBanner
    )

    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Install Pax8 MCP' }

    # Secrets preflight - fail fast BEFORE any agent config is touched
    $preflight = Test-KriticalPax8Secrets -SecretsDir $SecretsDir -TokenFileName $TokenFileName -NoBanner
    if (-not $preflight.Ok) {
        Write-Host '--- Secrets preflight FAILED ---' -ForegroundColor Red
        $preflight.Checks | Where-Object { -not $_.Pass } | Format-Table -AutoSize | Out-String | Write-Host
        throw "Cannot install — secrets preflight failed ($($preflight.FailedCount) check(s)). No agent configs modified."
    }

    $token = Read-KriticalPax8Token -SecretsDir $SecretsDir -TokenFileName $TokenFileName
    Write-Host ("Token loaded (length=" + $token.Length + " chars).") -ForegroundColor Green

    $allTargets = Get-KriticalPax8AgentTargets
    $selection = if ($Agent) {
        $allTargets | Where-Object { $_.Name -in $Agent }
    } else {
        $allTargets | Where-Object { $_.HostInstalled }
    }
    if (-not $Force.IsPresent) {
        $selection = $selection | Where-Object { $_.HostInstalled }
    }

    if (-not $selection) {
        Write-Warning "No agent targets selected/detected. Use -Force to wire a target without an installed host."
        return
    }

    # .5231 (lens-hunt): validate the token against the live server BEFORE rewriting any
    # agent config. Previously configs were written first and only probed at the end, so a
    # bad/expired token left every wired agent in a broken state the operator wouldn't notice
    # until restart. Fail fast here (skippable with -SkipProbe for offline installs).
    if (-not $SkipProbe.IsPresent) {
        Write-Host "Pre-validating token against mcp.pax8.com before touching agent configs..." -ForegroundColor DarkCyan
        $pre = Invoke-KriticalPax8McpInitialize -Token $token
        if (-not $pre.Ok) {
            throw ("Token pre-validation failed — no agent configs modified. " + ($pre.Error ? $pre.Error : "HTTP $($pre.StatusCode)") + " (use -SkipProbe to wire anyway).")
        }
        Write-Host ("  Token valid — server: " + $pre.ServerName + " v" + $pre.ServerVersion) -ForegroundColor Green
    }

    $rows = @()
    foreach ($t in $selection) {
        if ($PSCmdlet.ShouldProcess($t.Path, "Wire pax8 MCP")) {
            try {
                $res = Install-KriticalPax8McpForAgent -AgentName $t.Name -Token $token -IncludeOAuthEntry:$IncludeOAuthEntry
                $rows += [pscustomobject]@{
                    Agent     = $t.Name
                    Path      = $t.Path
                    Ok        = $true
                    Detail    = $res.ResultLine
                    Backup    = $res.Backup
                }
                Write-Host ("  [OK] " + $t.Name.PadRight(18) + " -> " + $t.Path) -ForegroundColor Green
            } catch {
                $rows += [pscustomobject]@{
                    Agent  = $t.Name
                    Path   = $t.Path
                    Ok     = $false
                    Detail = $_.Exception.Message
                    Backup = $null
                }
                Write-Host ("  [FAIL] " + $t.Name + " -> " + $_.Exception.Message) -ForegroundColor Red
            }
        }
    }

    $probe = $null
    if (-not $SkipProbe.IsPresent) {
        Write-Host ""
        Write-Host "Probing mcp.pax8.com with token..." -ForegroundColor DarkCyan
        $init = Invoke-KriticalPax8McpInitialize -Token $token
        if ($init.Ok) {
            $tools = Get-KriticalPax8McpToolList -Token $token
            Write-Host ("  Server: " + $init.ServerName + " v" + $init.ServerVersion + " | tools: " + $tools.ToolCount) -ForegroundColor Green
            $probe = [pscustomobject]@{
                Ok=$true; Server=$init.ServerName; Version=$init.ServerVersion; ToolCount=$tools.ToolCount
            }
        } else {
            Write-Host ("  [FAIL] " + ($init.Error ? $init.Error : "HTTP $($init.StatusCode)")) -ForegroundColor Red
            $probe = [pscustomobject]@{ Ok=$false; Error=$init.Error; StatusCode=$init.StatusCode }
        }
    }

    Write-Host ""
    Write-Host "=== Next steps ===" -ForegroundColor Yellow
    Write-Host "1. Close every running instance of the wired agent(s) (Claude Code panel, Codex session, Cursor, VS Code etc.)"
    Write-Host "2. Re-open. MCP servers register at session start only."
    Write-Host "3. Pax8 tools (21+ as of 2026-06-24) surface in the new session."
    Write-Host "4. Rotate token: replace the secrets file then re-run Install-KriticalPax8Mcp."

    [pscustomobject]@{
        Agents          = $rows
        Probe           = $probe
        TokenPath       = (Get-KriticalPax8TokenPath -SecretsDir $SecretsDir -TokenFileName $TokenFileName)
        RestartRequired = $true
    }
}
