#requires -Modules Pester
# Author: Joshua Finley - Kritical Pty Ltd

BeforeAll {
    $modPath = Join-Path $PSScriptRoot '..\..\src\Kritical.PS.Pax8Mcp.psd1'
    Import-Module $modPath -Force
    $script:Mod = Get-Module Kritical.PS.Pax8Mcp
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-pax8-agt-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempDir | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KriticalPax8AgentTargets' {
    It 'returns rows for the canonical 6 agent targets' {
        $rows = & $script:Mod { Get-KriticalPax8AgentTargets }
        $rows | Should -HaveCount 6
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'claude'
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'codex'
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'cursor'
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'continue'
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'vscode'
        ($rows | Select-Object -ExpandProperty Name) | Should -Contain 'vscode-insiders'
    }

    It 'every row has Path Format ConfigExists HostInstalled InstallHint' {
        $rows = & $script:Mod { Get-KriticalPax8AgentTargets }
        foreach ($r in $rows) {
            $r.Path           | Should -Not -BeNullOrEmpty
            $r.Format         | Should -BeIn @('json','toml')
            $r.ConfigExists   | Should -BeOfType [bool]
            $r.HostInstalled  | Should -BeOfType [bool]
            $r.InstallHint    | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Write-KriticalPax8JsonAgentConfig' {
    It 'writes a JSON config from scratch with pax8 entry containing token header' {
        $target = Join-Path $script:TempDir 'fresh.json'
        $res = & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'abcdefghijklmnopqrstuvwxyz0123456789' -IncludeOAuthEntry
        } $target
        Test-Path -LiteralPath $target | Should -BeTrue
        $obj = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        $obj.mcpServers.pax8 | Should -Not -BeNullOrEmpty
        $obj.mcpServers.pax8.type | Should -Be 'http'
        $obj.mcpServers.pax8.url  | Should -Match 'mcp.pax8.com'
        $obj.mcpServers.pax8.headers.'x-pax8-mcp-token' | Should -Be 'abcdefghijklmnopqrstuvwxyz0123456789'
        $obj.mcpServers.'pax8-oauth' | Should -Not -BeNullOrEmpty
    }

    It 'preserves pre-existing unrelated mcpServers entries' {
        $target = Join-Path $script:TempDir 'preserve.json'
        '{ "mcpServers": { "falcon-mcp": { "type": "stdio", "command": "uvx" } } }' | Set-Content -LiteralPath $target
        & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'abcdefghijklmnopqrstuvwxyz0123456789'
        } $target | Out-Null
        $obj = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        $obj.mcpServers.'falcon-mcp'.command | Should -Be 'uvx'
        $obj.mcpServers.pax8.headers.'x-pax8-mcp-token' | Should -Be 'abcdefghijklmnopqrstuvwxyz0123456789'
    }

    It 'is idempotent (re-running does not duplicate keys)' {
        $target = Join-Path $script:TempDir 'idempotent.json'
        & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        } $target | Out-Null
        & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        } $target | Out-Null
        $obj = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        # token should be updated, not added twice
        $obj.mcpServers.pax8.headers.'x-pax8-mcp-token' | Should -Be 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    }

    It '-RemoveOnly strips pax8 + pax8-oauth, leaves others' {
        $target = Join-Path $script:TempDir 'remove.json'
        & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'cccccccccccccccccccccccccccccccccccc' -IncludeOAuthEntry
        } $target | Out-Null
        # Add a falcon entry
        $cfg = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json -AsHashtable
        $cfg.mcpServers['falcon-mcp'] = @{ type='stdio'; command='uvx' }
        ($cfg | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $target

        & $script:Mod {
            param($t)
            Write-KriticalPax8JsonAgentConfig -Path $t -Token 'cccccccccccccccccccccccccccccccccccc' -RemoveOnly
        } $target | Out-Null
        $obj = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        $obj.mcpServers.'falcon-mcp' | Should -Not -BeNullOrEmpty
        ($obj.mcpServers.PSObject.Properties.Name -contains 'pax8')        | Should -BeFalse
        ($obj.mcpServers.PSObject.Properties.Name -contains 'pax8-oauth')  | Should -BeFalse
    }
}

Describe 'Write-KriticalPax8TomlAgentConfig' {
    It 'appends an [mcp_servers.pax8] block to a fresh toml file' {
        $target = Join-Path $script:TempDir 'fresh.toml'
        & $script:Mod {
            param($t)
            Write-KriticalPax8TomlAgentConfig -Path $t -Token 'dddddddddddddddddddddddddddddddddddd'
        } $target | Out-Null
        $body = Get-Content -LiteralPath $target -Raw
        $body | Should -Match '\[mcp_servers\.pax8\]'
        $body | Should -Match 'url = "https://mcp.pax8.com/v1/mcp"'
        $body | Should -Match 'enabled = true'
    }

    It 'is idempotent — replaces existing pax8 block without duplicating' {
        $target = Join-Path $script:TempDir 'idempotent.toml'
        @"
[mcp_servers.other]
url = "https://other"

[mcp_servers.pax8]
enabled = true
url = "https://OLD"
"@ | Set-Content -LiteralPath $target

        & $script:Mod {
            param($t)
            Write-KriticalPax8TomlAgentConfig -Path $t -Token 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
        } $target | Out-Null

        $body = Get-Content -LiteralPath $target -Raw
        ($body | Select-String '\[mcp_servers\.pax8\]' -AllMatches).Matches.Count | Should -Be 1
        $body | Should -Match '\[mcp_servers\.other\]'
        $body | Should -Match 'url = "https://mcp.pax8.com/v1/mcp"'
        $body | Should -Not -Match 'OLD'
    }

    It '-RemoveOnly strips pax8 block, leaves others' {
        $target = Join-Path $script:TempDir 'remove.toml'
        @"
[mcp_servers.other]
url = "https://other"

[mcp_servers.pax8]
enabled = true
url = "https://mcp.pax8.com/v1/mcp"
"@ | Set-Content -LiteralPath $target

        & $script:Mod {
            param($t)
            Write-KriticalPax8TomlAgentConfig -Path $t -Token 'f' -RemoveOnly
        } $target | Out-Null

        $body = Get-Content -LiteralPath $target -Raw
        $body | Should -Not -Match '\[mcp_servers\.pax8\]'
        $body | Should -Match '\[mcp_servers\.other\]'
    }
}
