# Kritical.PS.Pax8Mcp — Kritical Pax8 MCP Toolkit

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
      — If you found this, you were meant to —

---------------- A Seriously Kritical™ Production ----------------

                                   [] →
                 (¯`·.¸¸.·´¯)
               .·´            `·.        [] →
               `·.______________.·´
              |   +------------------+   |
              |   |     Kritical™     |  |
              |   |   []      []      |  |
              |   |                  |  |
              |   |   []  []  []     |  |
              |   +------------------+   |
                  (._.·´¯`·.¸_)

                     Your last call.
                   And your first move.

                         ★  ☆  ★

                     +61 1300 274 655
                 sales at kritical dot net

-----------------------------------------------------------------
```

**Author**: Joshua Finley — Kritical Pty Ltd — <https://kritical.net>
**License**: see [LICENSE](./LICENSE)
**Version**: 1.0.0

---

## What this is

A single PowerShell module that wires the **Pax8 hosted MCP server** (`https://mcp.pax8.com/v1/mcp`) into every supported agent on a Kritical operator machine and keeps it healthy.

Supported agents in v1.0.0:

| Agent | Config file | Format |
| --- | --- | --- |
| **Claude Code** (Anthropic) | `~/.claude.json` | JSON `mcpServers.pax8` |
| **Codex CLI** (OpenAI) | `~/.codex/config.toml` | TOML `[mcp_servers.pax8]` |
| **Cursor IDE** | `~/.cursor/mcp.json` | JSON `mcpServers.pax8` |
| **Continue.dev** | `~/.continue/config.json` | JSON `mcpServers.pax8` |
| **VS Code (stable)** | `%APPDATA%\Code\User\mcp.json` | JSON `mcpServers.pax8` |
| **VS Code Insiders** | `%APPDATA%\Code - Insiders\User\mcp.json` | JSON `mcpServers.pax8` |

Both Pax8 MCP auth paths are supported and can coexist:

| Entry | Auth | First-use experience |
| --- | --- | --- |
| `pax8` | Legacy `x-pax8-mcp-token` header (read from secrets folder) | Instant, no MFA |
| `pax8-oauth` | OAuth 2.1 + PKCE + Dynamic Client Registration | Browser opens → Pax8 MFA → tokens cached |

---

## Why a PowerShell module (and not a one-shot script)

- **Multi-machine**: every Kritical operator can install in one command and get an identical wiring.
- **Multi-agent**: a single source of truth across Claude / Codex / Cursor / Continue / VS Code rather than six bespoke setup guides.
- **Idempotent**: re-running `Install-KriticalPax8Mcp` is always safe; backs up each agent config before edits.
- **Auditable**: `Test-KriticalPax8Mcp` runs 7 gates and exits 0/1, ready to wire into a supervisor health pass.
- **Brand-locked**: every operator-facing output starts with the canonical Kritical banner (`SirJ's Deaddrop` / `A Seriously Kritical™ Production`).

---

## Install (operator machine)

### Option A — Local development install

```powershell
$src = "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.PS.Pax8Mcp\src"
Import-Module "$src\Kritical.PS.Pax8Mcp.psd1" -Force
```

### Option B — GitHub release (private repo today)

```powershell
# 1. Download the bundle
$zip = Join-Path $env:TEMP 'Kritical.PS.Pax8Mcp-1.0.0.zip'
gh release download v1.0.0 -R Sir-J-AU/Kritical.PS.Pax8Mcp -p '*.zip' -D $env:TEMP --clobber

# 2. Resolve the correct PSModulePath entry (handles OneDrive-mapped Documents)
$psMod = ($env:PSModulePath -split ';' |
          Where-Object { $_ -match 'Documents\\PowerShell\\Modules$' } |
          Select-Object -First 1)
$instDir = Join-Path $psMod 'Kritical.PS.Pax8Mcp\1.0.0'

# 3. Install + import + verify
if (Test-Path -LiteralPath $instDir) { Remove-Item -LiteralPath (Split-Path $instDir -Parent) -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $instDir -Force
Import-Module Kritical.PS.Pax8Mcp -Force
Test-KriticalPax8Secrets   # preflight — refuses if secrets folder isn't ready
Test-KriticalPax8Mcp       # 7-gate health probe
```

### Option C — PSGallery (once published)

```powershell
Install-Module Kritical.PS.Pax8Mcp -Scope CurrentUser
Import-Module  Kritical.PS.Pax8Mcp -Force
```

---

## Quickstart

```powershell
# 1. Ensure secrets folder contains the Pax8 MCP token (mint from app.pax8.com
#    Settings -> Integrations -> MCP server -> Connect -> Claude -> Option 2 Pax8 Token).
Test-Path "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt"

# 2. Install across every detected agent.
Install-KriticalPax8Mcp

# 3. Health probe — should return Ok=$true.
Test-KriticalPax8Mcp

# 4. Restart your agents (close Claude Code panel + re-open; same for Codex / Cursor / etc.).

# 5. Status report at any time.
Get-KriticalPax8McpStatus | Format-Table
```

---

## Public functions — what, why, how

### `Install-KriticalPax8Mcp`

Idempotent installer. Reads the token, backs up each target agent config, writes the `pax8` + (optionally) `pax8-oauth` entries, probes the live MCP, reports.

```powershell
# Auto-detect and install everywhere
Install-KriticalPax8Mcp

# One agent only
Install-KriticalPax8Mcp -Agent claude

# Token-only entry (no OAuth secondary)
Install-KriticalPax8Mcp -Agent claude -IncludeOAuthEntry:$false

# Force-write even when the host isn't installed yet (creates parent dirs)
Install-KriticalPax8Mcp -Agent cursor -Force
```

### `Get-KriticalPax8McpStatus`

Read-only inventory across every supported agent on this machine.

```powershell
Get-KriticalPax8McpStatus | Format-Table
# Shows per-agent: HostInstalled / ConfigExists / HasPax8Entry / HasOAuthEntry / HasTokenHeader
```

### `Test-KriticalPax8Mcp`

Comprehensive 7-gate health probe. Exits 0 when healthy.

```powershell
Test-KriticalPax8Mcp
# G1 SecretsFolder
# G2 TokenSane
# G3 OAuthDiscovery (RFC 8414 metadata at mcp.pax8.com)
# G4 McpInitialize (server identifies as pax8-mcp-server v1.0.0)
# G5 ToolsList (21+ tools)
# G6 AnyAgentWired (claude / codex / etc.)
# G7 WiredAgentTokenValid
```

### `Update-KriticalPax8McpToken`

Rotate the Pax8 MCP token. Prompts for the new value via `Read-Host -AsSecureString` (never echoed), backs up the old token file, writes the new one to the secrets folder, re-wires every currently-wired agent, re-probes.

```powershell
Update-KriticalPax8McpToken

# Non-interactive (e.g. supervisor / Hermes / CI)
Update-KriticalPax8McpToken -NewToken (Get-Content C:\drop\new-token.txt -Raw)
```

### `Remove-KriticalPax8Mcp`

Idempotent removal. Backs up each agent config, strips `pax8` + `pax8-oauth` entries, leaves all other MCP servers (`falcon-mcp` etc.) untouched. Token file in the secrets folder is preserved unless `-RemoveToken` is passed.

```powershell
Remove-KriticalPax8Mcp -Agent claude
Remove-KriticalPax8Mcp -RemoveToken   # full uninstall + move token aside
```

### Banner helpers

```powershell
Write-KriticalPax8Banner -Title 'Health Probe'            # interactive, brand colours
Get-KriticalPax8Banner -Title 'Health Probe' -Compact     # one-liner string for embedding
```

---

## How the agents are wired (precise shapes)

### JSON agents (Claude / Cursor / Continue / VS Code)

```json
{
  "mcpServers": {
    "pax8": {
      "type": "http",
      "url": "https://mcp.pax8.com/v1/mcp",
      "headers": {
        "x-pax8-mcp-token": "<read from Kritical secrets folder>"
      }
    },
    "pax8-oauth": {
      "type": "http",
      "url": "https://mcp.pax8.com/v1/mcp"
    }
  }
}
```

### TOML agent (Codex)

```toml
[mcp_servers.pax8]
enabled = true
url = "https://mcp.pax8.com/v1/mcp"
```

> Codex's MCP client handles OAuth Dynamic Client Registration when no token header is supplied; the token-header pattern is JSON-agent-specific.

---

## Secrets discipline (HARD RULES)

1. **Token only ever lives at**: `Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt` on the Kritical operator OneDrive.
2. **Token never lives in this repo**. Every config edit reads at runtime from that path.
3. **Never echoed**. `Read-KriticalPax8Token` returns the token only; no logging of the value.
4. **Backups stay out of git**: `.bak.krit-pax8mcp.<utc>` is auto-ignored by the parent toolkit `.gitignore`.
5. **Rotation**: re-mint at `app.pax8.com`, replace the file, run `Update-KriticalPax8McpToken`. Old token file is auto-backed up with `.bak.<utc>` suffix.

---

## Tests

### Unit

```powershell
cd "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.PS.Pax8Mcp"
.\tests\Invoke-AllTests.ps1 -SkipE2E
```

Covers:

- Banner read/format/Title/Compact/fallback.
- Token primitives: path joining, file presence, sane-length validation, trim handling.
- Agent target enumeration (6 canonical agents).
- JSON config writer: idempotent, preserves siblings, RemoveOnly.
- TOML config writer: idempotent, preserves siblings, RemoveOnly.

### E2E (live against mcp.pax8.com — requires secrets folder)

```powershell
.\tests\Invoke-AllTests.ps1
```

Covers:

- OAuth discovery endpoint returns valid metadata.
- `initialize` handshake with token returns `pax8-mcp-server` identity.
- `tools/list` returns ≥1 tool (currently 21).
- Full `Test-KriticalPax8Mcp` gate set passes.

---

## Publishing to PSGallery

See [docs/PUBLISHING.md](docs/PUBLISHING.md). High level:

1. Bump `ModuleVersion` in `src/Kritical.PS.Pax8Mcp.psd1`.
2. Run the full test suite green: `.\tests\Invoke-AllTests.ps1`.
3. `Test-ModuleManifest src\Kritical.PS.Pax8Mcp.psd1`.
4. `Publish-Module -Path src -NuGetApiKey <psgallery-key>`.

---

## Files

```text
Kritical.PS.Pax8Mcp/
├── README.md                                    ← this file
├── LICENSE
├── CONTRIBUTING.md
├── docs/
│   ├── PUBLISHING.md
│   ├── USAGE.md
│   └── ARCHITECTURE.md
├── src/
│   ├── Kritical.PS.Pax8Mcp.psd1                        ← module manifest (Author = Joshua Finley)
│   ├── Kritical.PS.Pax8Mcp.psm1                        ← root module
│   ├── Assets/
│   │   └── kritical-logo.txt                    ← canonical banner (verbatim)
│   ├── Private/
│   │   ├── _Banner.ps1
│   │   ├── _Token.ps1
│   │   ├── _McpProbe.ps1
│   │   └── _Agents.ps1
│   └── Public/
│       ├── Install-KriticalPax8Mcp.ps1
│       ├── Get-KriticalPax8McpStatus.ps1
│       ├── Test-KriticalPax8Mcp.ps1
│       ├── Update-KriticalPax8McpToken.ps1
│       └── Remove-KriticalPax8Mcp.ps1
└── tests/
    ├── Invoke-AllTests.ps1
    ├── Unit/
    │   ├── Banner.Tests.ps1
    │   ├── Token.Tests.ps1
    │   └── Agents.Tests.ps1
    └── E2E/
        └── LiveProbe.Tests.ps1
```

---

## Related Kritical packages

- **`Kritical-Pax8API`** — headless PowerShell client for the Pax8 **partner API** at `api.pax8.com` (client_credentials, no MFA). Use for scripts / supervisor / Hermes / cron. Complements (does not replace) the MCP path.
- **`Krit.PowerShellToolkit`** — shared Kritical utility scripts and the canonical `Krit.Banner.psm1` reader.
- **`Krit.ALToolkit`** — shared AL utilities for BC connectors.

---

## Support

- Hotline: +61 1300 274 655
- Email: sales at kritical dot net
- Web: <https://kritical.net>
