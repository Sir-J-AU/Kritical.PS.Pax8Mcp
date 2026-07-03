function Get-KriticalPax8TokenPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $SecretsDir,
        [string] $TokenFileName
    )
    if (-not $SecretsDir) {
        $SecretsDir = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos'
    }
    if (-not $TokenFileName) { $TokenFileName = 'pax8-mcpServer-auth.txt' }
    Join-Path $SecretsDir $TokenFileName
}

function Read-KriticalPax8Token {
    <#
    .SYNOPSIS
        Reads the Pax8 MCP token from the Kritical secrets folder. NEVER echoes it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $SecretsDir,
        [string] $TokenFileName,
        [switch] $AllowMissing
    )
    $path = Get-KriticalPax8TokenPath -SecretsDir $SecretsDir -TokenFileName $TokenFileName
    if (-not (Test-Path -LiteralPath $path)) {
        if ($AllowMissing) { return $null }
        throw "Pax8 MCP token file not found at $path. Mint one from app.pax8.com > Settings > Integrations > MCP server > Connect > Claude > Option 2 Pax8 Token (Legacy) and save to that exact path."
    }
    $token = (Get-Content -LiteralPath $path -Raw -ErrorAction Stop).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Pax8 MCP token file is empty at $path."
    }
    if ($token.Length -lt 16) {
        throw "Pax8 MCP token suspiciously short ($($token.Length) chars) at $path."
    }
    return $token
}

function Test-KriticalPax8TokenSane {
    <#
    .SYNOPSIS
        Returns $true when the token looks like a valid Pax8 MCP token shape.
        Pure validator — accepts $null / empty / whitespace and returns $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [AllowEmptyString()] [string] $Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    if ($Token.Length -lt 16 -or $Token.Length -gt 256) { return $false }
    if ($Token -match '\s') { return $false }
    return $true
}
