# Kritical.Pax8Mcp — Publishing to PSGallery

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
      — If you found this, you were meant to —

---------------- A Seriously Kritical™ Production ----------------
```

Author: Joshua Finley — Kritical Pty Ltd
Audience: Kritical release engineer (Joshua or delegate).

---

## Pre-flight (every release)

1. **Banner is canonical and verbatim.** `src/Assets/kritical-logo.txt` matches `Github-SecretsOutsideOfGitRepos\KriticalLogo.txt` byte-for-byte. Diff with:
   ```powershell
   $a = Get-Content -LiteralPath "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp\src\Assets\kritical-logo.txt" -Raw
   $b = Get-Content -LiteralPath "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\KriticalLogo.txt" -Raw
   if ($a -ne $b) { throw 'Bundled banner has drifted from canonical' }
   ```

2. **Author + branding stamp** in `src/Kritical.Pax8Mcp.psd1`:
   - `Author = 'Joshua Finley'`
   - `CompanyName = 'Kritical Pty Ltd'`
   - `Copyright` updated to current year.
   - No `Claude` / `Hermes` / `Codex` / `Copilot` / `GPT` strings anywhere.

3. **Tests all pass** (unit + e2e):
   ```powershell
   .\tests\Invoke-AllTests.ps1
   # PASS — exit 0
   ```

4. **No secrets in the repo** (token leak hunt):
   ```powershell
   $token = (Get-Content "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\pax8-mcpServer-auth.txt" -Raw).Trim()
   $prefix = $token.Substring(0,8)
   Get-ChildItem -Recurse -File | Where-Object { (Get-Content $_.FullName -Raw -EA SilentlyContinue) -match [regex]::Escape($prefix) }
   # Must return empty.
   ```

5. **Module manifest valid**:
   ```powershell
   Test-ModuleManifest src\Kritical.Pax8Mcp.psd1
   ```

6. **Version bumped** in `src/Kritical.Pax8Mcp.psd1` (`ModuleVersion`) + a `ReleaseNotes` entry added in the same commit.

---

## Publish steps

### Option 1 — PSGallery (recommended for distribution)

```powershell
# 1. Make sure you have a PSGallery API key.
#    Kritical operators: find at https://www.powershellgallery.com/account/apikeys
#    Save once: Set-Secret -Name PSGalleryApiKey -Vault Kritical
$apiKey = (Get-Secret -Name PSGalleryApiKey -AsPlainText)

# 2. Confirm folder layout matches what PSGallery expects.
#    PSGallery wants the .psd1 + .psm1 at the top of the package.
#    We have src/ — Publish-Module wants -Path pointing at the directory
#    that contains the .psd1 directly.

$publishRoot = "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp\src"
Publish-Module -Path $publishRoot -NuGetApiKey $apiKey -Verbose
```

### Option 2 — Private GitHub Release (no PSGallery)

```powershell
$repo = "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.Pax8Mcp"
Compress-Archive -Path "$repo\src\*","$repo\README.md","$repo\LICENSE","$repo\CONTRIBUTING.md","$repo\docs\*" -DestinationPath "$repo\Kritical.Pax8Mcp-1.0.0.zip" -Force
gh release create v1.0.0 "$repo\Kritical.Pax8Mcp-1.0.0.zip" -t 'Kritical.Pax8Mcp 1.0.0' -n (Get-Content "$repo\src\Kritical.Pax8Mcp.psd1" -Raw)
```

### Option 3 — Local network share (Kritical-internal)

```powershell
$share = '\\golem.kritical.lan\Modules\Kritical.Pax8Mcp'
Copy-Item -Recurse -Force "$repo\src\*" $share
```

Operators on the Kritical LAN can then:

```powershell
Import-Module \\golem.kritical.lan\Modules\Kritical.Pax8Mcp\Kritical.Pax8Mcp.psd1 -Force
```

---

## Post-publish

1. **Smoke-test the published package** from a fresh PowerShell:
   ```powershell
   # Force re-install from PSGallery, not the local dev copy
   Remove-Module Kritical.Pax8Mcp -ErrorAction SilentlyContinue
   Install-Module Kritical.Pax8Mcp -Force -Scope CurrentUser
   Import-Module Kritical.Pax8Mcp -Force

   # Banner renders
   Write-KriticalPax8Banner -Title 'Post-publish smoke test'

   # Health probe runs (will be 5/7 PASS on a fresh machine without secrets)
   Test-KriticalPax8Mcp -Quiet | Select-Object Total, Passed, Failed
   ```

2. **Update the operator runbook** (`Kritical.OperatorOnboarding`) with the published version pin.

3. **Tag the git commit** with `v<version>`:
   ```powershell
   git tag -a v1.0.0 -m "Kritical.Pax8Mcp 1.0.0 - initial release"
   git push origin v1.0.0
   ```

4. **Announce internally** via Kritical Teams channel.

---

## Rollback

```powershell
# Unpublish (PSGallery only allows for 90 days from publish):
Unpublish-Module -Name Kritical.Pax8Mcp -RequiredVersion 1.0.0 -NuGetApiKey $apiKey

# Or — publish a new patch with the broken function reverted and bump version.
```
