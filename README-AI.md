{
  "schema": "kritical-readme-ai/v1",
  "generatedUtc": "2026-07-16",
  "generatedFrom": ["src/Kritical.PS.Pax8Mcp.psd1 (incl ReleaseNotes + PrivateData.Kritical)", "src/Public/*.ps1 (synopses)", "src/Private/*.ps1"],
  "repo": {
    "name": "Kritical.PS.Pax8Mcp",
    "version": "1.0.0",
    "guid": "a5f8e4c2-6b3d-4a1e-9c7f-2d8b5e0a3f1c",
    "family": "Kritical.PS",
    "author": "Joshua Finley",
    "company": "Kritical Pty Ltd",
    "requiresPowerShell": "5.1",
    "compatibleEditions": ["Desktop", "Core"],
    "purpose": "Pax8 MCP wiring toolkit: installs/validates/rotates/removes the Pax8 hosted MCP server across supported agents (Claude Code, Codex, Cursor, generic MCP clients) via both legacy x-pax8-mcp-token header and OAuth 2.1 PKCE Dynamic Client Registration. Secrets stay in the Kritical secrets folder; no token lands in a repo.",
    "tags": ["Pax8", "MCP", "Kritical", "ClaudeCode", "Codex", "Cursor", "OAuth", "MSP", "Automation"]
  },
  "endpoints": {
    "mcp": "https://mcp.pax8.com/v1/mcp",
    "oauthDiscovery": "https://mcp.pax8.com/.well-known/oauth-authorization-server"
  },
  "secrets": {
    "canonicalDir": "…/Github-SecretsOutsideOfGitRepos",
    "tokenFile": "pax8-mcpServer-auth.txt",
    "posture": "token outside every repo; rotation via SecureString (no echo); preflight gate refuses wiring without token; never written to a repo-committable agent config"
  },
  "authPaths": [
    { "name": "legacy-header", "how": "x-pax8-mcp-token header from secrets token file" },
    { "name": "oauth-2.1-pkce-dcr", "how": "Dynamic Client Registration against OAuth discovery endpoint + PKCE code exchange" }
  ],
  "supportedAgents": ["Claude Code", "Codex", "Cursor", "generic MCP clients"],
  "publicApi": [
    { "name": "Install-KriticalPax8Mcp", "group": "lifecycle", "does": "install Pax8 hosted MCP server into one or more agents" },
    { "name": "Get-KriticalPax8McpStatus", "group": "lifecycle", "does": "report current wiring state across every supported agent" },
    { "name": "Test-KriticalPax8Mcp", "group": "lifecycle", "does": "comprehensive health probe for the toolkit" },
    { "name": "Update-KriticalPax8McpToken", "group": "lifecycle", "does": "rotate token; SecureString prompt (no echo) → secrets file" },
    { "name": "Remove-KriticalPax8Mcp", "group": "lifecycle", "does": "remove Pax8 MCP wiring from one or more agents" },
    { "name": "Test-KriticalPax8Secrets", "group": "secrets", "does": "preflight gate — verify secrets folder + token file present" },
    { "name": "Clear-KriticalPax8IngestedLogs", "group": "hygiene", "does": "clean test-output / wave-receipt / run-log files" },
    { "name": "Write-KriticalPax8Banner", "group": "banner", "does": "emit brand banner" },
    { "name": "Get-KriticalPax8Banner", "group": "banner", "does": "return brand banner" }
  ],
  "privateApi": [
    { "name": "_Agents", "file": "src/Private/_Agents.ps1", "role": "per-agent config read/write (Claude Code / Codex / Cursor / generic)" },
    { "name": "_Token", "file": "src/Private/_Token.ps1", "role": "secrets-file token read + SecureString handling" },
    { "name": "_McpProbe", "file": "src/Private/_McpProbe.ps1", "role": "MCP endpoint health probe" },
    { "name": "_Banner", "file": "src/Private/_Banner.ps1", "role": "banner internals" }
  ],
  "exportCount": 9,
  "publicFileCount": 7,
  "typicalFlow": ["Test-KriticalPax8Secrets", "Install-KriticalPax8Mcp", "Get-KriticalPax8McpStatus", "Test-KriticalPax8Mcp", "Update-KriticalPax8McpToken"],
  "estateRole": {
    "role": "how agents reach the Pax8 hosted MCP surface; central to Pax8 integration the connector depends on",
    "siblings": ["L15 Pax8 recipe/OpenAPI synthesis (D:/kritical/pax8-devx)"]
  },
  "testCoverage": {
    "l6Rank": "Tier 1 zero-first-party-test target",
    "releaseNotesClaim": "Pester unit + e2e test suite",
    "caveat": "confirm live tests/ contents (file-presence != coverage)",
    "firstTargets": ["_Token SecureString round-trip", "_Agents per-agent config writer (mock agent config paths)"]
  },
  "provenance": {
    "note": "Generated from live manifest (incl release notes + PrivateData.Kritical) + public source tree. New files only (README-HUMAN.md + README-AI.md); README.md not touched.",
    "lane": "L4 (NIGHT-SHIFT-WORKLIST)",
    "repoOrdinal": "9th repo in L4 sweep; also L6 Tier-1 test-gap target"
  }
}
