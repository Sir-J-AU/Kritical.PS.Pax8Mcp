function Clear-KriticalPax8IngestedLogs {
    <#
    .SYNOPSIS
        Cleans up Kritical.PS.Pax8Mcp test-output, wave-receipt and run-log files that
        have been ingested into a downstream sink (Application Insights / PaxBrain
        SQL / OneDrive cold archive). Files NOT yet ingested are preserved.

    .DESCRIPTION
        Walks the configured log/artefact directories and per-file decides:

            - INGESTED  -> delete (or move to .recycle/<utc>/ if -Soft)
            - PENDING   -> keep
            - UNKNOWN   -> keep (default-safe — never delete without proof)

        Default sinks scanned:
            * $env:LOCALAPPDATA\Kritical\Kritical.PS.Pax8Mcp\test-output
            * <repo>\tests\output   (legacy — only swept if -IncludeRepoTestOutput)
            * Any -ExtraPath the operator passes

        Ingestion proof is one of (per-file):
            a) Presence of `<file>.ingested.<utc>` marker beside the file.
            b) Path appears in the optional manifest CSV `-IngestManifestPath`
               with column `Path` matching exact full-path.
            c) Sidecar JSON `<file>.sink.json` carrying `ingested: true`.

        Without ANY of (a)/(b)/(c), the file is treated as PENDING and left alone.
        This is intentional — silent deletion of un-ingested data is worse than
        leaving a few extra files on disk.

    .PARAMETER OlderThan
        Only consider files older than this TimeSpan. Default: 24 hours.

    .PARAMETER Soft
        Move to a .recycle subdir instead of deleting. Recoverable for 30 days.

    .PARAMETER WhatIf
        Standard PowerShell — show what would be deleted without doing it.

    .EXAMPLE
        Clear-KriticalPax8IngestedLogs -WhatIf

    .EXAMPLE
        Clear-KriticalPax8IngestedLogs -Soft

    .EXAMPLE
        Clear-KriticalPax8IngestedLogs -ExtraPath C:\temp\krit-logs -IngestManifestPath C:\ingested.csv

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    [OutputType([pscustomobject])]
    param(
        [string[]] $ExtraPath,
        [string]   $IngestManifestPath,
        [TimeSpan] $OlderThan = ([TimeSpan]::FromHours(24)),
        [switch]   $Soft,
        [switch]   $IncludeRepoTestOutput,
        [switch]   $NoBanner
    )

    if (-not $NoBanner.IsPresent) { Write-KriticalPax8Banner -Title 'Clear Ingested Logs' -Compact }

    # Build scan paths
    $paths = [System.Collections.Generic.List[string]]::new()
    $defaultOut = Join-Path $env:LOCALAPPDATA 'Kritical\Kritical.PS.Pax8Mcp\test-output'
    if (Test-Path -LiteralPath $defaultOut) { $paths.Add($defaultOut) }
    if ($IncludeRepoTestOutput.IsPresent) {
        $repoOut = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'tests\output'
        if (Test-Path -LiteralPath $repoOut) { $paths.Add($repoOut) }
    }
    foreach ($p in ($ExtraPath ?? @())) {
        if (Test-Path -LiteralPath $p) { $paths.Add($p) }
        else { Write-Warning "Skip — extra path not found: $p" }
    }

    if ($paths.Count -eq 0) {
        Write-Host 'No log directories found to scan.' -ForegroundColor Yellow
        return [pscustomobject]@{ Scanned=0; Ingested=0; Pending=0; Unknown=0; Deleted=0; Path=@() }
    }

    # Build manifest set
    $manifestSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($IngestManifestPath -and (Test-Path -LiteralPath $IngestManifestPath)) {
        try {
            Import-Csv -LiteralPath $IngestManifestPath | ForEach-Object {
                if ($_.PSObject.Properties.Name -contains 'Path' -and $_.Path) {
                    [void]$manifestSet.Add($_.Path)
                }
            }
            Write-Host ("Manifest loaded: " + $manifestSet.Count + " ingested entries.") -ForegroundColor DarkGray
        } catch {
            Write-Warning "Failed to parse ingest manifest: $($_.Exception.Message)"
        }
    }

    $cutoff = (Get-Date) - $OlderThan
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($dir in $paths) {
        Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Name -notmatch '\.ingested\.|\.sink\.json$|\.recycle' } |
          ForEach-Object {
              $f = $_.FullName
              # Determine ingestion status
              $status = 'UNKNOWN'
              # .5231 (lens-hunt): dropped a `Test-Path -LiteralPath "$f.ingested.*"` check —
              # in -LiteralPath mode the * is a literal char, so it never matched an
              # `<file>.ingested.<utc>` marker and ingested files were wrongly kept as UNKNOWN.
              # The Get-ChildItem -Filter glob below is the correct marker probe.
              if ((Get-ChildItem -LiteralPath (Split-Path -Parent $f) -Filter ((Split-Path -Leaf $f) + '.ingested.*') -ErrorAction SilentlyContinue)) { $status = 'INGESTED' }
              elseif ($manifestSet.Contains($f)) { $status = 'INGESTED' }
              elseif (Test-Path -LiteralPath ("$f.sink.json")) {
                  try {
                      $j = Get-Content -LiteralPath ("$f.sink.json") -Raw | ConvertFrom-Json
                      if ($j.ingested -eq $true) { $status = 'INGESTED' } else { $status = 'PENDING' }
                  } catch { $status = 'UNKNOWN' }
              } else {
                  $status = 'PENDING'
              }

              $row = [pscustomobject]@{
                  Path   = $f
                  Status = $status
                  Size   = $_.Length
                  Age    = ((Get-Date) - $_.LastWriteTime)
                  Action = 'KEEP'
              }

              if ($status -eq 'INGESTED') {
                  if ($PSCmdlet.ShouldProcess($f, ($Soft.IsPresent ? 'Move to .recycle/' : 'Delete (ingested)'))) {
                      try {
                          if ($Soft.IsPresent) {
                              # .5231 (lens-hunt): second-resolution timestamps collide when the
                              # function runs twice inside the same second, and a same-named file in
                              # two source dirs would overwrite inside the shared recycle bucket.
                              # Append a short random suffix per destination to keep the audit trail intact.
                              $recycle = Join-Path $dir (".recycle\" + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6)))
                              New-Item -ItemType Directory -Path $recycle -Force -ErrorAction SilentlyContinue | Out-Null
                              Move-Item -LiteralPath $f -Destination (Join-Path $recycle (Split-Path -Leaf $f)) -Force
                              $row.Action = 'RECYCLED'
                          } else {
                              Remove-Item -LiteralPath $f -Force
                              $row.Action = 'DELETED'
                          }
                      } catch {
                          $row.Action = 'ERROR:' + $_.Exception.Message
                      }
                  } else {
                      $row.Action = 'WOULD-DELETE'
                  }
              }

              $rows.Add($row)
          }
    }

    $ingested = @($rows | Where-Object Status -eq 'INGESTED').Count
    $pending  = @($rows | Where-Object Status -eq 'PENDING').Count
    $unknown  = @($rows | Where-Object Status -eq 'UNKNOWN').Count
    $deleted  = @($rows | Where-Object Action -match '^(DELETED|RECYCLED)$').Count

    Write-Host ''
    Write-Host ("Scanned:  " + $rows.Count)  -ForegroundColor DarkCyan
    Write-Host ("Ingested: $ingested (acted: $deleted)") -ForegroundColor Green
    Write-Host ("Pending:  $pending (kept)") -ForegroundColor Yellow
    Write-Host ("Unknown:  $unknown (kept)") -ForegroundColor Yellow

    [pscustomobject]@{
        Scanned   = $rows.Count
        Ingested  = $ingested
        Pending   = $pending
        Unknown   = $unknown
        Deleted   = $deleted
        Mode      = if ($Soft.IsPresent) { 'Soft' } else { 'Hard' }
        Path      = @($paths)
        Rows      = @($rows)
    }
}
