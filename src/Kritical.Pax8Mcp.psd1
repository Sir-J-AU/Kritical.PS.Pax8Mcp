@{
    RootModule        = 'Kritical.Pax8Mcp.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a5f8e4c2-6b3d-4a1e-9c7f-2d8b5e0a3f1c'
    Author            = 'Joshua Finley'
    CompanyName       = 'Kritical Pty Ltd'
    Copyright         = '(c) 2026 Kritical Pty Ltd. All rights reserved.'
    Description       = 'Kritical Pax8 MCP wiring toolkit. Installs, validates, rotates and removes the Pax8 hosted MCP server across every supported agent (Claude Code, Codex, Cursor, generic MCP clients) using both legacy x-pax8-mcp-token and OAuth 2.1 PKCE Dynamic Client Registration paths. Secrets stay in the Kritical secrets folder; no token ever lands in a repo.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')

    FunctionsToExport = @(
        'Install-KriticalPax8Mcp'
        'Get-KriticalPax8McpStatus'
        'Test-KriticalPax8Mcp'
        'Test-KriticalPax8Secrets'
        'Update-KriticalPax8McpToken'
        'Remove-KriticalPax8Mcp'
        'Clear-KriticalPax8IngestedLogs'
        'Write-KriticalPax8Banner'
        'Get-KriticalPax8Banner'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Pax8','MCP','Kritical','ClaudeCode','Codex','Cursor','OAuth','MSP','Automation')
            LicenseUri   = 'https://kritical.net/legal/license'
            ProjectUri   = 'https://kritical.net'
            IconUri      = 'https://kritical.net/assets/horizontal_logo.png'
            ReleaseNotes = @'
1.0.0 — Initial release.
  * Multi-agent installer for Claude Code, Codex, Cursor, generic MCP clients.
  * Legacy x-pax8-mcp-token header path + OAuth 2.1 PKCE DCR path.
  * Pester unit + e2e test suite.
  * Kritical-branded banner + logo.
  * Joshua Finley, Kritical Pty Ltd.
'@
        }
        Kritical = @{
            CanonicalSecretsDir = 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos'
            TokenFileName       = 'pax8-mcpServer-auth.txt'
            McpEndpoint         = 'https://mcp.pax8.com/v1/mcp'
            OAuthDiscovery      = 'https://mcp.pax8.com/.well-known/oauth-authorization-server'
        }
    }
}
