#requires -Modules Pester
# Author: Joshua Finley - Kritical Pty Ltd

BeforeAll {
    $modPath = Join-Path $PSScriptRoot '..\..\src\Kritical.Pax8Mcp.psd1'
    Import-Module $modPath -Force

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-pax8-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempDir | Out-Null

    # Token primitives are internal; access via module scope
    $mod = Get-Module Kritical.Pax8Mcp
    $script:GetPath  = { param($d,$f) & $mod { param($a,$b) Get-KriticalPax8TokenPath -SecretsDir $a -TokenFileName $b } $d $f }
    $script:ReadTok  = { param($d,$f,$am) & $mod { param($a,$b,$am) Read-KriticalPax8Token -SecretsDir $a -TokenFileName $b -AllowMissing:$am } $d $f $am }
    $script:Sane     = { param($t) & $mod { param($x) Test-KriticalPax8TokenSane -Token $x } $t }
}

AfterAll {
    Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KriticalPax8TokenPath' {
    It 'joins SecretsDir + TokenFileName' {
        $p = & $script:GetPath 'C:\sec' 'foo.txt'
        $p | Should -Be 'C:\sec\foo.txt'
    }

    It 'defaults TokenFileName to pax8-mcpServer-auth.txt' {
        $p = & $script:GetPath 'C:\sec' $null
        $p | Should -Match 'pax8-mcpServer-auth\.txt$'
    }
}

Describe 'Read-KriticalPax8Token' {
    It 'throws when file missing and -AllowMissing not set' {
        { & $script:ReadTok $script:TempDir 'absent.txt' $false } | Should -Throw -ExpectedMessage '*not found*'
    }

    It 'returns $null when file missing and -AllowMissing set' {
        $r = & $script:ReadTok $script:TempDir 'absent.txt' $true
        $r | Should -BeNullOrEmpty
    }

    It 'throws when file empty' {
        $f = Join-Path $script:TempDir 'empty.txt'
        '' | Set-Content -LiteralPath $f
        { & $script:ReadTok $script:TempDir 'empty.txt' $false } | Should -Throw -ExpectedMessage '*empty*'
    }

    It 'throws when token shorter than 16 chars' {
        $f = Join-Path $script:TempDir 'short.txt'
        'tooshort' | Set-Content -LiteralPath $f -NoNewline
        { & $script:ReadTok $script:TempDir 'short.txt' $false } | Should -Throw -ExpectedMessage '*short*'
    }

    It 'returns trimmed token when valid' {
        $f = Join-Path $script:TempDir 'good.txt'
        "   abcdefghijklmnopqrstuvwxyz0123456789   `r`n" | Set-Content -LiteralPath $f -NoNewline
        $r = & $script:ReadTok $script:TempDir 'good.txt' $false
        $r | Should -Be 'abcdefghijklmnopqrstuvwxyz0123456789'
    }
}

Describe 'Test-KriticalPax8TokenSane' {
    It 'rejects null + empty + whitespace' {
        & $script:Sane $null    | Should -BeFalse
        & $script:Sane ''       | Should -BeFalse
        & $script:Sane '   '    | Should -BeFalse
    }
    It 'rejects too short' {
        & $script:Sane 'abc123' | Should -BeFalse
    }
    It 'rejects token containing whitespace' {
        & $script:Sane 'abc123 def456ghi7890' | Should -BeFalse
    }
    It 'accepts 36-char alphanumeric (Pax8 legacy shape)' {
        & $script:Sane '4abcdefghijklmnopqrstuvwxyz0123456789' | Should -BeTrue
    }
}
