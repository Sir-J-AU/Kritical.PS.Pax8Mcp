# Contributing to Kritical.Pax8Mcp

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
      — If you found this, you were meant to —

---------------- A Seriously Kritical™ Production ----------------
```

Author: Joshua Finley — Kritical Pty Ltd — https://kritical.net

This module is Kritical-authored and intended primarily for Kritical operators and Kritical customer engagements. Outside contributions require a Contributor License Agreement; reach Kritical at +61 1300 274 655 or `sales at kritical dot net` before opening a PR.

---

## Local development setup

1. Clone the repo to `~/OneDrive - Kritical Pty Ltd/Github/Kritical.Pax8Mcp/` (or anywhere on a Kritical operator OneDrive).
2. PowerShell 7+ required for most paths (PowerShell 5.1 works for everything except a few `??` operator sites).
3. Pester 5.5+ required for tests.

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

4. Python 3.11+ on PATH (used for safe JSON edits where case-collision keys break PowerShell's ConvertFrom-Json).

---

## Branch + commit hygiene

- One feature per branch. Branch name `feature/<short-purpose>` or `fix/<short-purpose>`.
- Commit messages: `<type>(<scope>): <subject>` where type is `feat | fix | refactor | docs | test | chore`.
- Never commit secrets. Token file lives at `Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt` only.
- Run the full test suite green before opening a PR.

---

## Code standards

- `Set-StrictMode -Version Latest` at the top of every file.
- `$ErrorActionPreference = 'Stop'` at the top of any operator-facing entry point.
- Comment-based help on every public function — `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` per parameter, `.EXAMPLE`, `.NOTES` (with `Author: Joshua Finley - Kritical Pty Ltd`).
- Private helpers go in `src/Private/` and are dot-sourced by the root module.
- Public functions go in `src/Public/` and are listed verbatim in `FunctionsToExport` of the `.psd1`.
- Brand: every operator-facing path calls `Write-KriticalPax8Banner` (full) or `-Compact` at start. No AI-agent banners ever.
- No abbreviations of `Kritical™` to `Kritical` in customer-facing strings.

---

## Adding a new agent target

1. Add a row to `Get-KriticalPax8AgentTargets` in `src/Private/_Agents.ps1` with Name / Format / Path / InstallHint.
2. If a new format (not JSON or TOML), add a `Write-KriticalPax8XxxAgentConfig` private writer in `_Agents.ps1` and wire it into `Install-KriticalPax8McpForAgent`.
3. Add unit tests in `tests/Unit/Agents.Tests.ps1` covering: fresh-write, idempotent re-write, preserves siblings, `-RemoveOnly`.
4. Update README's "Supported agents" table.

---

## Running tests

```powershell
cd "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp"
.\tests\Invoke-AllTests.ps1            # full unit + live e2e
.\tests\Invoke-AllTests.ps1 -SkipE2E   # CI / offline
```

Test runner output lands in `tests/output/results-<utc>.xml` (NUnitXml) + `summary-<utc>.json`. Exit code: 0 = all pass, 1 = any failure.

---

## Versioning

Semantic versioning per the manifest.

- PATCH (`1.0.x`): bug fix, no API change.
- MINOR (`1.x.0`): new agent target, new optional parameter, additive change.
- MAJOR (`x.0.0`): rename or remove an exported function, change a parameter contract.

Bump the version in `src/Kritical.Pax8Mcp.psd1` and add a `ReleaseNotes` entry in `PSData.ReleaseNotes` in the same commit.

---

## Publishing

See [docs/PUBLISHING.md](docs/PUBLISHING.md).
