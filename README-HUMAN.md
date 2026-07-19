# [PS-MODULE] Kritical.PS.Pax8Mcp — README (human)

> Kritical's **Pax8 MCP wiring toolkit** — installs, validates, rotates and removes the
> Pax8 hosted MCP server across every supported agent (Claude Code, Codex, Cursor, generic
> MCP clients) using **both** the legacy `x-pax8-mcp-token` header path **and** the OAuth 2.1
> PKCE Dynamic Client Registration path. Secrets live in the Kritical secrets folder —
> **no token ever lands in a repo.**

| | |
|---|---|
| **Module** | `Kritical.PS.Pax8Mcp` |
| **Version** | 1.0.0 |
| **Requires** | PowerShell **5.1+** — `Desktop` **and** `Core` |
| **Public surface** | **9 functions** |
| **MCP endpoint** | `https://mcp.pax8.com/v1/mcp` |
| **OAuth discovery** | `https://mcp.pax8.com/.well-known/oauth-authorization-server` |
| **Secrets** | `…/Github-SecretsOutsideOfGitRepos/pax8-mcpServer-auth.txt` (outside any repo) |
| **Author** | Joshua Finley · (c) 2026 Kritical Pty Ltd |

---

## What it does

Wiring a hosted MCP server into an AI agent by hand is fiddly and per-agent. This module
makes it **one idempotent call per lifecycle stage** (install / status / test / rotate /
remove) that works across Claude Code, Codex, Cursor, and generic MCP clients — while
keeping the auth token in the canonical Kritical secrets folder, never in a config a repo
could commit.

## Two auth paths (both supported)

| Path | When | How |
|---|---|---|
| **Legacy header** | Simple token auth | `x-pax8-mcp-token` header, value from the secrets token file |
| **OAuth 2.1 PKCE DCR** | Modern flow | Dynamic Client Registration against the OAuth discovery endpoint, PKCE code exchange |

## Function map (9 public)

### Lifecycle
| Function | Does |
|---|---|
| `Install-KriticalPax8Mcp` | Installs the Pax8 hosted MCP server into one or more agents on this machine. |
| `Get-KriticalPax8McpStatus` | Reports the current Pax8 MCP wiring state across every supported agent. |
| `Test-KriticalPax8Mcp` | Comprehensive health probe for the toolkit on this machine. |
| `Update-KriticalPax8McpToken` | Rotate the token — prompts for the new value as a `SecureString` (no echo), writes to the secrets file. |
| `Remove-KriticalPax8Mcp` | Removes the Pax8 MCP wiring from one or more agents. |

### Secrets & hygiene
| Function | Does |
|---|---|
| `Test-KriticalPax8Secrets` | Preflight gate — verifies the Kritical secrets folder + token file are in place before any wiring op. |
| `Clear-KriticalPax8IngestedLogs` | Cleans up test-output / wave-receipt / run-log files. |

### Banner
| Function | Does |
|---|---|
| `Write-KriticalPax8Banner` / `Get-KriticalPax8Banner` | Canonical Kritical brand banner (Pax8-tagged). |

### Typical flow

```powershell
Import-Module Kritical.PS.Pax8Mcp
Test-KriticalPax8Secrets                 # gate: token file present?
Install-KriticalPax8Mcp -Agent ClaudeCode,Cursor
Get-KriticalPax8McpStatus                # confirm wiring across agents
Test-KriticalPax8Mcp                     # health probe
Update-KriticalPax8McpToken              # rotate (SecureString prompt) when needed
```

## Secrets posture (why it's estate-trusted)

- **Token lives outside every repo:** `Github-SecretsOutsideOfGitRepos/pax8-mcpServer-auth.txt`
  (declared in the manifest's `PrivateData.Kritical.CanonicalSecretsDir`).
- **Rotation via `SecureString`** — no plaintext echo, no token in shell history.
- **Preflight gate** (`Test-KriticalPax8Secrets`) refuses to wire without the token file present.
- No token is ever written into an agent config that a repo could commit.

## Private internals

```
src/Private/_Agents.ps1     per-agent config read/write (Claude Code / Codex / Cursor / generic)
src/Private/_Token.ps1      secrets-file token read + SecureString handling
src/Private/_McpProbe.ps1   MCP endpoint health probe
src/Private/_Banner.ps1     banner internals
```

## Estate role & test-coverage flag

- Central to the **Pax8 integration** the connector depends on — this is how agents reach
  the Pax8 hosted MCP surface (companion to the L15 Pax8 recipe/OpenAPI synthesis work).
- The **L6 PS-TEST-COVERAGE-MAP flagged this a Tier-1 zero-first-party-test target.** The
  release notes claim a "Pester unit + e2e test suite" — confirm the live `tests/` contents
  (file-presence ≠ coverage). First targets: `_Token` SecureString round-trip and the
  `_Agents` per-agent config writer (mock the agent config paths).

## Repo layout

```
src/Kritical.PS.Pax8Mcp.psd1   manifest v1.0.0 (9 exports; canonical secrets + endpoints in PrivateData.Kritical)
src/Kritical.PS.Pax8Mcp.psm1   loader
src/Public/*.ps1               7 files → 9 exported functions (banner pair grouped)
src/Private/*.ps1              _Agents · _Token · _McpProbe · _Banner
src/Assets/kritical-logo.txt   ASCII banner asset
tests/ · tools/ · scripts/ · docs/
```

## Family relationships

- **Pax8 integration siblings:** the L15 recipe-synthesis + OpenAPI work (`D:\kritical\pax8-devx`).
- **Brand banner** mirrors the `Get-Kritical*Banner` pattern used across the Kritical.PS family.

---

*Companion machine doc: `README-AI.md` (schema `kritical-readme-ai/v1`). Generated from
live manifest (incl. release notes + PrivateData) + public source tree — new file, does not
touch `README.md`.*
