#requires -Modules Pester
# Pester 5+ unit tests for the Kritical.PS.Pax8Mcp banner functions.
# Author: Joshua Finley - Kritical Pty Ltd

BeforeAll {
    $modPath = Join-Path $PSScriptRoot '..\..\src\Kritical.PS.Pax8Mcp.psd1'
    Import-Module $modPath -Force
}

Describe 'Get-KriticalPax8Banner' {
    It 'returns the canonical SirJ Deaddrop banner when secrets folder is present' {
        $b = Get-KriticalPax8Banner
        $b | Should -Match 'SirJ'
        $b | Should -Match 'Kritical'
        $b | Should -Match '1300 274 655'
    }

    It '-Compact returns one-line summary' {
        $b = Get-KriticalPax8Banner -Compact
        $b | Should -Match 'Kritical'
        $b.Split("`n").Count | Should -BeLessOrEqual 1
    }

    It '-Title appends a title block when not Compact' {
        $b = Get-KriticalPax8Banner -Title 'UnitTest'
        $b | Should -Match '--- UnitTest ---'
    }

    It 'falls back gracefully when LogoPath does not exist' {
        $b = Get-KriticalPax8Banner -LogoPath 'C:\does\not\exist\logo.txt'
        $b | Should -Match 'Kritical'
    }
}

Describe 'Write-KriticalPax8Banner' {
    It 'does not throw' {
        { Write-KriticalPax8Banner -Title 'UnitTest' -NoColor } | Should -Not -Throw
    }

    It 'compact form does not throw' {
        { Write-KriticalPax8Banner -Compact -NoColor } | Should -Not -Throw
    }
}
