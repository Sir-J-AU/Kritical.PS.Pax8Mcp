# Stale-scope truncation findings — Kritical.PS.Pax8Mcp

**Provenance**

| Field | Value |
|---|---|
| Date (UTC, absolute) | 2026-07-25T04:11Z – 05:20Z |
| Repo | `Kritical.PS.Pax8Mcp` |
| Branch | `master` |
| Commit SHA at observation | `51e8e81ddf2f7be17a5dba959d1458ba91504cf1` |
| Working tree at observation | clean — **nothing in this repo was modified**, this is a findings document only |
| Estate-level report | `C:\temp\STALE-SCOPE-TRUNCATION-HUNT-20260725.md` |

**Bug class hunted.** A filter, range, list, limit or timeout is hardcoded once; the codebase
or its upstream data grows past it; the code keeps reporting SUCCESS while covering only a
fraction of what it claims. It never errors. It always looks green.

> **No code in this repo was changed by this hunt.** Findings are reports. Severity ranking and
> the estate-wide picture are in the estate-level report above.

---
## M6 (MEDIUM) — the live E2E asserts 5 of 7 gates, and its floor cannot detect a dropped gate

`tests/E2E/LiveProbe.Tests.ps1:50, 64`

```powershell
L50: $r.Total | Should -BeGreaterOrEqual 6
L64: $criticalGates = @('G1.SecretsFolder','G2.TokenSane','G3.OAuthDiscovery','G4.McpInitialize','G5.ToolsList')
```

**Authoritative source:** the gates `Test-KriticalPax8Mcp.ps1` actually registers.

**Computed exclusion — extracted every `addGate '...'` call:** 7 distinct gates —
`G1.SecretsFolder, G2.TokenSane, G3.OAuthDiscovery, G4.McpInitialize, G5.ToolsList,
G6.AnyAgentWired, G7.WiredAgentTokenValid`.

**2 of 7 (28.6%)** — `G6.AnyAgentWired` and `G7.WiredAgentTokenValid` — are never asserted.
Worse, the `Total -ge 6` floor **cannot detect a gate being dropped from 7 to 6**.

Note the whole `It` is `-Skip:(-not $HaveSecrets)`, so with no secrets present it shows as
Skipped — that part is honest and visible.

**Evidence:** VERIFIED-BY-EXECUTION (source extraction).

## Recommended fix
Assert `$r.Total -eq 7` (an exact pin fails loud when a gate is added or removed) and include
G6/G7 in `$criticalGates`.
---

## Method

Multiple independent detection methods were used throughout, because **a low count from one
detector means the detector missed, not that the code is clean**: ripgrep regex sweeps,
PowerShell `Select-String` over enumerated file censuses, and — where quantification was
needed — direct execution, AST introspection, manifest parsing, or filesystem enumeration.

**Note on tooling:** `rg` is **not** on PATH inside the Bash tool on this host. The first
sweep of this hunt returned 0 hits for every pattern; that was a detector failure, not a clean
result. Use the Grep tool or PowerShell `Select-String`, and verify any zero with a second
method.

**Evidence tags** used above: VERIFIED-BY-EXECUTION (command run, output quoted) /
READ-FROM-SOURCE / INFERRED / UNKNOWN. A skip is never recorded as a pass.
