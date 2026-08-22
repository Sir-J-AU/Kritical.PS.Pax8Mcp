#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $agentsPath = Join-Path $repo 'src/Private/_Agents.ps1'
    $clearPath = Join-Path $repo 'src/Public/Clear-KriticalPax8IngestedLogs.ps1'
    $installPath = Join-Path $repo 'src/Public/Install-KriticalPax8Mcp.ps1'
    $testPath = Join-Path $repo 'src/Public/Test-KriticalPax8Mcp.ps1'
    $script:Agents = Get-Content -LiteralPath $agentsPath -Raw
    $script:Clear = Get-Content -LiteralPath $clearPath -Raw
    $script:Install = Get-Content -LiteralPath $installPath -Raw
    $script:TestMcp = Get-Content -LiteralPath $testPath -Raw
    foreach ($p in @($agentsPath,$clearPath,$installPath,$testPath)) {
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
        if (@($errors).Count) { throw "Parse errors in $p: $(@($errors|ForEach-Object Message) -join '; ')" }
    }
}

Describe '.5231 Pax8 MCP regression guards' {
    It 'keeps config paths/endpoints opaque to generated Python source' {
        $script:Agents | Should -Match "os\.environ\['KRIT_PAX8_CFG_PATH'\]"
        $script:Agents | Should -Match "os\.environ\['KRIT_PAX8_ENDPOINT'\]"
        $script:Agents | Should -Match '\$env:KRIT_PAX8_CFG_PATH\s*=\s*\$Path'
        $script:Agents | Should -Match '\$env:KRIT_PAX8_ENDPOINT\s*=\s*\$McpEndpoint'
        $script:Agents | Should -Not -Match "path\s*=\s*r'\$Path'"
        $script:Agents | Should -Not -Match "'url':'\$McpEndpoint'"
        $script:Agents | Should -Not -Match 'C:\\Users\\joshl\\AppData\\Local\\Python'
    }

    It 'uses real marker globbing and collision-resistant recycle buckets' {
        $script:Clear | Should -Not -Match 'Test-Path\s+-LiteralPath\s+\("\$f\.ingested\.\*"\)'
        $script:Clear | Should -Match 'Get-ChildItem\s+-LiteralPath[^\r\n]+-Filter[^\r\n]+\.ingested\.\*'
        $script:Clear | Should -Match "NewGuid\(\)\.ToString\('N'\)\.Substring\(0,6\)"
    }

    It 'validates the live token before any agent config write unless SkipProbe is explicit' {
        $probeAt = $script:Install.IndexOf('Invoke-KriticalPax8McpInitialize -Token $token')
        $writeLoopAt = $script:Install.IndexOf('foreach ($t in $selection)')
        $writeAt = $script:Install.IndexOf('Install-KriticalPax8McpForAgent')
        $probeAt | Should -BeGreaterThan -1
        $writeLoopAt | Should -BeGreaterThan $probeAt
        $writeAt | Should -BeGreaterThan $probeAt
        $script:Install | Should -Match 'if \(-not \$SkipProbe\.IsPresent\)'
        $script:Install | Should -Match 'Token pre-validation failed — no agent configs modified'
    }

    It 'surfaces token-read failure detail in G2 instead of swallowing it' {
        $script:TestMcp | Should -Match '\$tokenErr\s*=\s*\$null'
        $script:TestMcp | Should -Match 'catch\s*\{\s*\$tokenErr\s*=\s*\$_\.Exception\.Message\s*\}'
        $script:TestMcp | Should -Match 'length=0 err='
        $script:TestMcp | Should -Not -Match 'Read-KriticalPax8Token[^\r\n]+catch\s*\{\s*\}'
    }
}
