# Multi-agent detection + per-agent config writers.
# Each agent gets a Detect-* + Install-* + Remove-* + Get-Status-* primitive.
# Agents supported in v1:
#   - claude   (Claude Code, $HOME\.claude.json, JSON, mcpServers)
#   - codex    (OpenAI Codex CLI, $HOME\.codex\config.toml, TOML, [mcp_servers.X])
#   - cursor   (Cursor IDE, $HOME\.cursor\mcp.json, JSON, mcpServers)
#   - continue (Continue.dev VSCode/JetBrains, $HOME\.continue\config.json, JSON)
#   - vscode-mcp (VS Code generic mcp.json: $env:APPDATA\Code\User\mcp.json — Insiders + stable)
# Each writer is idempotent + backs up before edit.

function Get-KriticalPax8AgentTargets {
    <#
    .SYNOPSIS
        Returns the canonical list of supported agent targets, with detected state per machine.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()
    $home = $env:USERPROFILE
    $appdata = $env:APPDATA
    $targets = @(
        @{ Name='claude';     Format='json'; Path=(Join-Path $home '.claude.json');                                    InstallHint='Claude Code (Anthropic)' }
        @{ Name='codex';      Format='toml'; Path=(Join-Path $home '.codex/config.toml');                              InstallHint='OpenAI Codex CLI' }
        @{ Name='cursor';     Format='json'; Path=(Join-Path $home '.cursor/mcp.json');                                InstallHint='Cursor IDE' }
        @{ Name='continue';   Format='json'; Path=(Join-Path $home '.continue/config.json');                           InstallHint='Continue.dev' }
        @{ Name='vscode';     Format='json'; Path=(Join-Path $appdata 'Code/User/mcp.json');                           InstallHint='VS Code (stable)' }
        @{ Name='vscode-insiders'; Format='json'; Path=(Join-Path $appdata 'Code - Insiders/User/mcp.json');           InstallHint='VS Code Insiders' }
    )
    foreach ($t in $targets) {
        $exists = Test-Path -LiteralPath $t.Path
        # parent existence = signal the host tool is installed; .json/.toml may be auto-created on first launch
        $parentExists = Test-Path -LiteralPath (Split-Path -Parent $t.Path)
        [pscustomobject]@{
            Name         = $t.Name
            Format       = $t.Format
            Path         = $t.Path
            ConfigExists = $exists
            ParentExists = $parentExists
            HostInstalled = ($exists -or $parentExists)
            InstallHint   = $t.InstallHint
        }
    }
}

# --- JSON writer (Claude Code, Cursor, Continue, vscode mcp.json) ---
function Write-KriticalPax8JsonAgentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Token,
        [string] $McpEndpoint = 'https://mcp.pax8.com/v1/mcp',
        [switch] $IncludeOAuthEntry,
        [switch] $RemoveOnly
    )
    # Resolve Python for safe JSON editing (handles case-collision keys etc.)
    # .5231 (lens-hunt): drop the hardcoded per-user (C:\Users\joshl) python path —
    # it is non-portable across operator machines. Honour an optional override via
    # $env:KRITICAL_PAX8_PYTHON, then fall back to well-known versioned install roots.
    $pyExe = $null
    $pyCandidates = @()
    if ($env:KRITICAL_PAX8_PYTHON) { $pyCandidates += $env:KRITICAL_PAX8_PYTHON }
    $pyCandidates += @(
        'C:\Python314\python.exe','C:\Python313\python.exe','C:\Python312\python.exe','C:\Python311\python.exe'
    )
    foreach ($p in $pyCandidates) { if ($p -and (Test-Path -LiteralPath $p)) { $pyExe = $p; break } }
    if (-not $pyExe) {
        foreach ($n in 'py.exe','python3.14.exe','python.exe','python3.exe') {
            $c = Get-Command $n -ErrorAction SilentlyContinue
            if ($c -and $c.Source -notlike '*WindowsApps*') { $pyExe = $c.Source; break }
        }
    }
    if (-not $pyExe) { throw "Python 3 required to edit JSON agent configs (handles case-collision keys cleanly)." }

    # Backup
    $bak = $null
    if (Test-Path -LiteralPath $Path) {
        $utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
        $bak = "$Path.bak.krit-pax8mcp.$utc"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
    } else {
        # Make parent + seed empty
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -LiteralPath $Path -Value '{}' -Encoding UTF8
    }

    $skipOAuth = if ($IncludeOAuthEntry.IsPresent) { '0' } else { '1' }
    $remove    = if ($RemoveOnly.IsPresent) { '1' } else { '0' }

    # .5231 (lens-hunt): pass $Path and $McpEndpoint into Python via the environment
    # rather than interpolating them into the source string. Interpolating a path
    # containing a single-quote or trailing backslash (e.g. C:\Users\bob\ or ...'s folder\)
    # broke the r'...' literal and could inject arbitrary Python; the same held for a
    # crafted $McpEndpoint bleeding into the JSON. env vars are opaque to the parser.
    $pyCode = @"
import json,sys,os
path = os.environ['KRIT_PAX8_CFG_PATH']
endpoint = os.environ['KRIT_PAX8_ENDPOINT']
token = sys.stdin.read().strip()
skip_oauth = '$skipOAuth' == '1'
remove_only = '$remove' == '1'
try:
    with open(path,'r',encoding='utf-8') as f:
        d = json.load(f)
except Exception:
    d = {}
if not isinstance(d, dict): d = {}
mcp = d.setdefault('mcpServers', {})
if remove_only:
    for k in ('pax8','pax8-oauth'):
        if k in mcp: del mcp[k]
else:
    mcp['pax8'] = {
        'type':'http',
        'url':endpoint,
        'headers': {'x-pax8-mcp-token': token}
    }
    if not skip_oauth:
        mcp['pax8-oauth'] = {'type':'http','url':endpoint}
    elif 'pax8-oauth' in mcp:
        del mcp['pax8-oauth']
with open(path,'w',encoding='utf-8') as f:
    json.dump(d,f,indent=2,ensure_ascii=False)
print('OK keys=' + ','.join(sorted(mcp.keys())))
"@
    $env:KRIT_PAX8_CFG_PATH = $Path
    $env:KRIT_PAX8_ENDPOINT = $McpEndpoint
    try {
        $result = $Token | & $pyExe -c $pyCode
    } finally {
        Remove-Item Env:\KRIT_PAX8_CFG_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\KRIT_PAX8_ENDPOINT -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        Path       = $Path
        Backup     = $bak
        Tool       = 'python-json'
        Keys       = ($result -replace '^OK keys=','').Split(',')
        ResultLine = $result
    }
}

# --- TOML writer (Codex config.toml) ---
function Write-KriticalPax8TomlAgentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Token,
        [string] $McpEndpoint = 'https://mcp.pax8.com/v1/mcp',
        [switch] $RemoveOnly
    )
    # Codex MCP entries are toml `[mcp_servers.<name>]` blocks. We append/replace
    # the `[mcp_servers.pax8]` block. Codex uses OAuth-based remote MCP shape so
    # the token does not embed into the toml (different from Claude). We retain
    # the existing url-only entry as the operative path.
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -LiteralPath $Path -Value '' -Encoding UTF8
    }
    $utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
    $bak = "$Path.bak.krit-pax8mcp.$utc"
    Copy-Item -LiteralPath $Path -Destination $bak -Force

    $content = Get-Content -LiteralPath $Path -Raw
    # Strip any prior [mcp_servers.pax8] block (best-effort: from header to next blank-line + bracket)
    $stripped = [regex]::Replace(
        $content,
        '(?ms)^\[mcp_servers\.pax8\][^\[]*?(?=^\[|\Z)',
        ''
    )
    if ($RemoveOnly.IsPresent) {
        [System.IO.File]::WriteAllText($Path, $stripped.TrimEnd() + "`n", [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{
            Path       = $Path
            Backup     = $bak
            Tool       = 'toml-regex'
            Removed    = $true
            ResultLine = 'OK removed pax8'
        }
    }
    $appendix = @"

[mcp_servers.pax8]
enabled = true
url = "$McpEndpoint"
"@
    $newContent = $stripped.TrimEnd() + "`n" + $appendix.TrimStart() + "`n"
    [System.IO.File]::WriteAllText($Path, $newContent, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        Path       = $Path
        Backup     = $bak
        Tool       = 'toml-regex'
        Removed    = $false
        ResultLine = 'OK keys=pax8'
    }
}

# --- Per-agent dispatcher ---
function Install-KriticalPax8McpForAgent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AgentName,
        [Parameter(Mandatory)] [string] $Token,
        [string] $McpEndpoint = 'https://mcp.pax8.com/v1/mcp',
        [switch] $IncludeOAuthEntry,
        [switch] $RemoveOnly
    )
    $targets = Get-KriticalPax8AgentTargets
    $t = $targets | Where-Object Name -eq $AgentName | Select-Object -First 1
    if (-not $t) { throw "Unknown agent name: $AgentName. Valid: $($targets.Name -join ', ')" }
    if ($t.Format -eq 'json') {
        Write-KriticalPax8JsonAgentConfig -Path $t.Path -Token $Token -McpEndpoint $McpEndpoint -IncludeOAuthEntry:$IncludeOAuthEntry -RemoveOnly:$RemoveOnly
    } elseif ($t.Format -eq 'toml') {
        Write-KriticalPax8TomlAgentConfig -Path $t.Path -Token $Token -McpEndpoint $McpEndpoint -RemoveOnly:$RemoveOnly
    } else {
        throw "Unsupported format $($t.Format) for agent $AgentName"
    }
}
