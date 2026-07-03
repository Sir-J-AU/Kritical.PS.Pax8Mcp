# Kritical.Pax8Mcp — Detailed Usage Guide

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
      — If you found this, you were meant to —

---------------- A Seriously Kritical™ Production ----------------
```

Author: Joshua Finley — Kritical Pty Ltd
Audience: Kritical operators + Kritical-trained engineers.

This is the prove-it-fucking-works guide. Every command below has been validated against the live `mcp.pax8.com` endpoint on 2026-06-24 with the production-shape OAuth and legacy-token flows.

---

## Table of contents

1. [What problem this solves](#what-problem-this-solves)
2. [The two Pax8 auth surfaces — DO NOT confuse](#the-two-pax8-auth-surfaces--do-not-confuse)
3. [Prerequisites](#prerequisites)
4. [End-to-end: from zero to "21 tools surfacing in Claude Code"](#end-to-end-from-zero-to-21-tools-surfacing-in-claude-code)
5. [Function-by-function reference](#function-by-function-reference)
6. [Proving it works](#proving-it-works)
7. [Failure modes + recovery](#failure-modes--recovery)
8. [Cross-agent matrix](#cross-agent-matrix)
9. [Security model](#security-model)

---

## What problem this solves

Pax8 publishes a hosted MCP server (`https://mcp.pax8.com/v1/mcp`) that surfaces 21 Pax8 partner-API tools (list-companies, list-products, get-product-pricing, list-invoices, list-orders, submit-order, semantic-search-product, etc.) to any MCP-aware chat agent.

Wiring it up by hand:
- Has six different config-file shapes to learn (Claude vs Codex vs Cursor vs Continue vs VS Code vs VS Code Insiders).
- Has two auth paths (legacy token header vs OAuth 2.1 PKCE DCR) with materially different operator UX.
- Is easy to corrupt (each agent has its own JSON/TOML peculiarities and case-collision keys).
- Spreads secrets everywhere if done sloppily.

This module turns that into one PowerShell command per machine, with all secrets staying in the Kritical secrets folder.

---

## The two Pax8 auth surfaces — DO NOT confuse

| Layer | Endpoint | Auth | When to use |
|---|---|---|---|
| **Hosted MCP** | `mcp.pax8.com/v1/mcp` | (a) `x-pax8-mcp-token` header from `app.pax8.com` portal, OR (b) OAuth 2.1 + PKCE + DCR | Interactive Claude/Codex/Cursor sessions. 21 tools. |
| **Partner API** | `api.pax8.com` | `client_credentials` grant against `token-manager.pax8.com/oauth/token` using `PAX8_CLIENT_ID` / `PAX8_CLIENT_SECRET` env vars | Scripts, supervisor, Hermes, cron, headless automation |

This module wires column 1.
The sister `Kritical-Pax8API` PowerShell module covers column 2.
They are different systems with different credentials. Holding the partner-API creds does NOT grant MCP access (and vice versa).

---

## Prerequisites

| Requirement | How to confirm |
|---|---|
| OneDrive synced to `C:\Users\joshl\OneDrive - Kritical Pty Ltd\` | `Test-Path "$env:USERPROFILE\OneDrive - Kritical Pty Ltd"` |
| Kritical secrets folder present | `Test-Path "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos"` |
| Pax8 MCP token file present | `Test-Path "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt"` |
| Python 3.11+ on PATH (for safe JSON edits) | `python --version` (must NOT be the Microsoft Store shim) |
| PowerShell 5.1 or 7+ | `$PSVersionTable.PSVersion` |
| Pester 5.5+ (only for running tests) | `Get-Module Pester -ListAvailable` |

If the token file isn't present, mint one:

1. Browser to https://app.pax8.com
2. Settings → Integrations → MCP server → Connect → Claude
3. Choose Option 2: Pax8 Token (Legacy). Copy the 36-character token.
4. Save it to: `C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt` (no BOM, no trailing newline matters).

---

## End-to-end: from zero to "21 tools surfacing in Claude Code"

```powershell
# Step 1: load the module
$root = "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp"
Import-Module "$root\src\Kritical.Pax8Mcp.psd1" -Force

# Step 2: confirm token is in place
Test-Path "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt"
# True

# Step 3: install across every detected agent
Install-KriticalPax8Mcp
# Banner + per-agent status + live probe (server pax8-mcp-server v1.0.0, 21 tools)

# Step 4: verify
Test-KriticalPax8Mcp
# 7 gates -> ALL PASS

# Step 5: status report
Get-KriticalPax8McpStatus | Select-Object -ExpandProperty Agents | Format-Table

# Step 6: restart Claude Code (close + re-open)
# 21 pax8-* tools now surface in the new session.
```

---

## Function-by-function reference

### `Install-KriticalPax8Mcp`

| Parameter | Type | Purpose |
|---|---|---|
| `-Agent <string[]>` | string[] | Agent names to wire. Default: every detected. Valid: claude / codex / cursor / continue / vscode / vscode-insiders. |
| `-SecretsDir` | string | Override the canonical secrets folder. |
| `-TokenFileName` | string | Override the canonical token filename. |
| `-IncludeOAuthEntry` | switch | Default `$true`. Also write the `pax8-oauth` secondary entry. |
| `-Force` | switch | Wire even when the host's parent dir isn't present (creates it). |
| `-SkipProbe` | switch | Skip the live mcp.pax8.com probe. |
| `-NoBanner` | switch | Suppress the brand banner (for embedded use). |

**Side effects**: Backs up each agent config to `<config>.bak.krit-pax8mcp.<utc>` before edit.

**Output**: PSCustomObject with `Agents[]` (per-target rows), `Probe`, `TokenPath`, `RestartRequired=$true`.

### `Get-KriticalPax8McpStatus`

Read-only. Reports per-agent: `HostInstalled` / `ConfigExists` / `HasPax8Entry` / `HasOAuthEntry` / `HasTokenHeader`. Also reports `TokenPath` + `TokenPresent` at the top level.

### `Test-KriticalPax8Mcp`

Runs 7 gates and returns `{ Gates[], Passed, Failed, Total, Ok }`. Use `-Quiet` to suppress host output (returns object only). Wire into a supervisor health pass via:

```powershell
$r = Test-KriticalPax8Mcp -Quiet
if (-not $r.Ok) { throw "Pax8 MCP unhealthy — $($r.Failed) of $($r.Total) gates failed" }
```

### `Update-KriticalPax8McpToken`

Interactive rotate: prompts for the new token via `Read-Host -AsSecureString` (no echo, no clipboard exposure), backs up the old token to `<token-file>.bak.<utc>`, writes the new one, re-wires every currently-wired agent, re-probes.

Non-interactive rotate (for supervisor / Hermes):

```powershell
$newTok = Get-Content C:\drop\fresh-pax8.txt -Raw
Update-KriticalPax8McpToken -NewToken $newTok
```

### `Remove-KriticalPax8Mcp`

Inverse of Install. Strips `pax8` + `pax8-oauth` entries from the targeted agent(s). Leaves all other MCP servers (e.g. `falcon-mcp`) untouched. Token file stays unless `-RemoveToken` is passed.

### `Write-KriticalPax8Banner` / `Get-KriticalPax8Banner`

Brand-banner helpers. Use anywhere a script needs the canonical Kritical banner.

---

## Proving it works

### Proof 1 — OAuth metadata reachable

```powershell
Import-Module "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp\src\Kritical.Pax8Mcp.psd1" -Force
$mod = Get-Module Kritical.Pax8Mcp
& $mod { Test-KriticalPax8McpOAuthDiscovery } | Format-List
# Issuer                : https://mcp.pax8.com/v1
# AuthorizeEndpoint     : https://mcp.pax8.com/v1/authorize
# TokenEndpoint         : https://mcp.pax8.com/v1/token
# RegistrationEndpoint  : https://mcp.pax8.com/v1/register
# Scopes                : { Manage:Pax8Data, offline_access, openid, profile, email }
```

### Proof 2 — Token works against the live MCP

```powershell
$token = & $mod { Read-KriticalPax8Token }
& $mod { param($t) Invoke-KriticalPax8McpInitialize -Token $t } $token | Format-List
# Ok            : True
# StatusCode    : 200
# ServerName    : pax8-mcp-server
# ServerVersion : 1.0.0
```

### Proof 3 — 21 tools surfacing

```powershell
$tools = & $mod { param($t) Get-KriticalPax8McpToolList -Token $t } $token
$tools.ToolCount     # 21
$tools.Tools | Select-Object -First 5
# get-pax8-help-documents
# pax8-get-company-by-uuid
# pax8-get-detailed-usage-summary
# pax8-get-hitl-result
# pax8-get-invoice-by-uuid
```

### Proof 4 — Every gate green

```powershell
Test-KriticalPax8Mcp
# G1 SecretsFolder           True
# G2 TokenSane               True   (length=36)
# G3 OAuthDiscovery          True   (issuer=https://mcp.pax8.com/v1 ...)
# G4 McpInitialize           True   (server=pax8-mcp-server v1.0.0)
# G5 ToolsList               True   (toolCount=21 sample=...)
# G6 AnyAgentWired           True   (claude)
# G7 WiredAgentTokenValid    True   (status=200)
# ALL 7 GATES PASS - Pax8 MCP healthy.
```

### Proof 5 — Unit tests

```powershell
.\tests\Invoke-AllTests.ps1 -SkipE2E
# PASS — 30+ tests; ~1.5s total.
```

### Proof 6 — E2E live tests

```powershell
.\tests\Invoke-AllTests.ps1
# Includes Proof 1-4 as Pester tests; produces tests/output/results-<utc>.xml
```

---

## Failure modes + recovery

| Symptom | Cause | Fix |
|---|---|---|
| `Pax8 MCP token file not found` | First-time setup, token never minted | Browser to `app.pax8.com` → Settings → Integrations → MCP server → Connect → Claude → Option 2 → save to canonical secrets path |
| `HTTP 401` from initialize | Token rotated / revoked on Pax8 side | `Update-KriticalPax8McpToken` to mint + re-wire |
| `HTTP 401` with `WWW-Authenticate: Bearer` but no `Missing x-pax8-mcp-token header` body | OAuth path being used without DCR completion | Restart Claude Code → browser MFA on first call → tokens cache |
| `Python 3 required to edit JSON agent configs` | Python missing or only Microsoft Store shim found | Install Python 3.11+ from python.org. Or `winget install Python.Python.3.13` |
| `Cannot index into a null array` from PowerShell | Trying to ConvertFrom-Json on `~/.claude.json` with case-colliding project keys | This module avoids that via Python-shim writer. If you hit this in a custom script, switch to `ConvertFrom-Json -AsHashtable` or use this module's `Write-KriticalPax8JsonAgentConfig`. |
| Tools don't surface after install | Agent wasn't restarted | Close + re-open. MCP servers load at session start only. |
| `pax8-oauth` triggers browser every time | OAuth tokens not persisting | Check the agent's MCP token cache (Claude: `~/.claude/mcp-needs-auth-cache.json`). For Claude Code, deleting the stale row + retry usually fixes. |

---

## Cross-agent matrix

Exact paths + entry shapes per supported agent.

### Claude Code (Anthropic)

- Config: `~/.claude.json`
- Format: JSON, top-level `mcpServers` map.
- Entry shape:
  ```json
  "mcpServers": {
    "pax8": {
      "type": "http",
      "url": "https://mcp.pax8.com/v1/mcp",
      "headers": { "x-pax8-mcp-token": "<token>" }
    },
    "pax8-oauth": { "type": "http", "url": "https://mcp.pax8.com/v1/mcp" }
  }
  ```

### Codex (OpenAI)

- Config: `~/.codex/config.toml`
- Format: TOML.
- Entry shape:
  ```toml
  [mcp_servers.pax8]
  enabled = true
  url = "https://mcp.pax8.com/v1/mcp"
  ```

### Cursor IDE

- Config: `~/.cursor/mcp.json`
- Format: JSON, top-level `mcpServers` map (same shape as Claude).

### Continue.dev

- Config: `~/.continue/config.json`
- Format: JSON. The module writes `mcpServers.pax8` even though Continue's primary config uses `mcpServers` differently; verify version compatibility before relying on this in production.

### VS Code stable / VS Code Insiders

- Config: `%APPDATA%\Code\User\mcp.json` (stable) or `%APPDATA%\Code - Insiders\User\mcp.json`
- Format: JSON, top-level `mcpServers` map. Requires MCP-aware extension (Cline / Continue / official MCP extension).

---

## Security model

1. **Token lives only in the Kritical secrets folder.** Never in this repo. Never in Claude/Codex/Cursor config except as a runtime-resolved value at install time.
2. **Token rotation** is one command (`Update-KriticalPax8McpToken`). Old token file is auto-backed up; replace the live file in the secrets folder and re-run.
3. **No echoing**. `Read-Host -AsSecureString` for interactive entry. `Read-KriticalPax8Token` returns the value to the caller only — never logs / writes it.
4. **Backups stay out of git** via `*.bak.*` patterns in the parent repo `.gitignore`.
5. **No third-party data plane**. All MCP traffic goes directly from your agent to `mcp.pax8.com` over TLS. This module doesn't proxy or log.
6. **AppLocker / device policy**: this module ships PowerShell only. No signed binaries. If your tenant blocks unsigned scripts, sign the `.psm1` per Kritical's code-signing policy before deploying.

---

For the architecture write-up — module shape, function decomposition, design choices — see [ARCHITECTURE.md](ARCHITECTURE.md).
For publishing to PSGallery — see [PUBLISHING.md](PUBLISHING.md).
