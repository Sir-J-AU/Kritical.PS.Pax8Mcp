#requires -Modules Pester
# Live e2e tests — require the operator's Pax8 secrets folder + token to be present.
# Skipped automatically when the secrets folder is not on this machine.
# Author: Joshua Finley - Kritical Pty Ltd

BeforeDiscovery {
    $tokenPath = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt'
    $script:HaveSecrets = Test-Path -LiteralPath $tokenPath
}

BeforeAll {
    $modPath = Join-Path $PSScriptRoot '..\..\src\Kritical.PS.Pax8Mcp.psd1'
    Import-Module $modPath -Force
    $script:Mod = Get-Module Kritical.PS.Pax8Mcp
}

Describe 'OAuth discovery (no token required)' {
    It 'mcp.pax8.com OAuth metadata is reachable and well-formed' {
        $r = & $script:Mod { Test-KriticalPax8McpOAuthDiscovery }
        $r.Ok                 | Should -BeTrue
        $r.Issuer             | Should -Match 'mcp\.pax8\.com'
        $r.AuthorizeEndpoint  | Should -Match '/authorize'
        $r.TokenEndpoint      | Should -Match '/token'
        $r.Scopes             | Should -Contain 'Manage:Pax8Data'
    }
}

Describe 'Token-auth MCP path (requires Kritical secrets folder)' -Skip:(-not $HaveSecrets) {
    It 'initialize handshake returns server name pax8-mcp-server' {
        $token = & $script:Mod { Read-KriticalPax8Token }
        $r = & $script:Mod { param($t) Invoke-KriticalPax8McpInitialize -Token $t } $token
        $r.Ok | Should -BeTrue
        $r.ServerName | Should -Be 'pax8-mcp-server'
        $r.ServerVersion | Should -Not -BeNullOrEmpty
    }

    It 'tools/list returns at least 1 tool' {
        $token = & $script:Mod { Read-KriticalPax8Token }
        $r = & $script:Mod { param($t) Get-KriticalPax8McpToolList -Token $t } $token
        $r.Ok | Should -BeTrue
        $r.ToolCount | Should -BeGreaterOrEqual 1
        $r.Tools | Should -Contain 'pax8-list-companies'
    }
}

Describe 'Test-KriticalPax8Mcp comprehensive gate set' {
    It 'returns a structured result with Gates / Passed / Failed / Total / Ok' {
        $r = Test-KriticalPax8Mcp -Quiet
        $r.Gates  | Should -Not -BeNullOrEmpty
        $r.Total  | Should -BeGreaterOrEqual 6
        $r.Passed | Should -BeOfType [int]
        $r.Failed | Should -BeOfType [int]
        $r.Ok     | Should -BeOfType [bool]
    }

    It 'reports G3 OAuth discovery PASS regardless of token presence' {
        $r = Test-KriticalPax8Mcp -Quiet
        $g3 = $r.Gates | Where-Object Gate -eq 'G3.OAuthDiscovery'
        $g3.Pass | Should -BeTrue
    }

    It 'reports critical G1-G5 PASS when secrets folder + token present' -Skip:(-not $HaveSecrets) {
        $r = Test-KriticalPax8Mcp -Quiet
        $criticalGates = @('G1.SecretsFolder','G2.TokenSane','G3.OAuthDiscovery','G4.McpInitialize','G5.ToolsList')
        foreach ($g in $criticalGates) {
            $row = $r.Gates | Where-Object Gate -eq $g
            $row.Pass | Should -BeTrue -Because "G $g must pass when secrets present (live e2e)"
        }
    }
}
