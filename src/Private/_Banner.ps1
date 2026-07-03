function Get-KriticalPax8BannerCanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    # Resolution order (first found wins):
    # 1) Public Kritical-Branding folder (canonical home for the public banner)
    # 2) Legacy secrets-folder location (backward compat — pre-1.1)
    # 3) Module-bundled fallback (fresh installs / CI / non-Kritical machines)
    $candidates = @(
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Kritical-Branding\public\KriticalLogo.txt'),
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\KriticalLogo.txt'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'Assets/kritical-logo.txt')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-KriticalPax8Banner {
    <#
    .SYNOPSIS
        Returns the canonical Kritical banner verbatim (SirJ's Deaddrop / A Seriously Kritical(TM) Production).
    .DESCRIPTION
        Reads the canonical banner from the operator's secrets folder so any future
        edit to the master copy at KriticalLogo.txt propagates to every consumer.
        Falls back to the module-bundled asset if the secrets folder is not present.
    .EXAMPLE
        Get-KriticalPax8Banner -Title 'Install'
    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Title,
        [switch] $Compact,
        [string] $LogoPath
    )
    if ($Compact) {
        $line = "[Kritical(TM)] A Seriously Kritical Production | +61 1300 274 655 | sales at kritical dot net"
        if ($Title) { $line += " - $Title" }
        return $line
    }
    if (-not $LogoPath) { $LogoPath = Get-KriticalPax8BannerCanonicalPath }
    if (-not $LogoPath -or -not (Test-Path -LiteralPath $LogoPath)) {
        $line = "[Kritical(TM)] A Seriously Kritical Production | +61 1300 274 655 | sales at kritical dot net"
        if ($Title) { $line += "`n--- $Title ---" }
        return $line
    }
    $logo = Get-Content -LiteralPath $LogoPath -Raw
    if ($Title) { return ($logo.TrimEnd() + "`n`n--- $Title ---`n") }
    return $logo
}

function Write-KriticalPax8Banner {
    <#
    .SYNOPSIS
        Writes the canonical Kritical banner to host with brand colours.
    .EXAMPLE
        Write-KriticalPax8Banner -Title 'Health Probe' -Compact
    #>
    [CmdletBinding()]
    param(
        [string] $Title,
        [switch] $Compact,
        [switch] $NoColor,
        [string] $LogoPath
    )
    $useColor = -not $NoColor.IsPresent -and $null -ne $Host.UI.RawUI -and $null -ne $Host.UI.RawUI.ForegroundColor
    $banner = Get-KriticalPax8Banner -Title $Title -Compact:$Compact -LogoPath $LogoPath
    if (-not $useColor) {
        Write-Output $banner
        return
    }
    foreach ($l in ($banner -split "`r?`n")) {
        $color = 'DarkCyan'
        if ($l -match 'Kritical™|SirJ|first move|last call|Seriously Kritical|---\s|★|☆') { $color = 'Yellow' }
        elseif ($l -match '274 655|kritical dot net') { $color = 'DarkCyan' }
        Write-Host $l -ForegroundColor $color
    }
}
