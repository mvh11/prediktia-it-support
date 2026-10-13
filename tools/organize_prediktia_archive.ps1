[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ControlPlaneRoot,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    [System.IO.Path]::GetFullPath($Path)
}

function Test-LikelySecretPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $name = [System.IO.Path]::GetFileName($Path)
    $lower = $name.ToLowerInvariant()
    $exact = @('.env','.env.local','.env.production','.env.development','id_rsa','id_dsa','id_ecdsa','id_ed25519')
    if ($exact -contains $lower) { return $true }
    if ($lower -match '(^|[._-])(credential|credentials|secret|secrets|token|tokens|private[-_]?key)([._-]|$)') { return $true }
    if ($lower -match '\.(pem|p12|pfx|key)$') { return $true }
    return $false
}

function Get-RelativePathSafe {
    param([string]$Base,[string]$Path)
    [System.IO.Path]::GetRelativePath($Base,$Path)
}

function Get-ItemSha256 {
    param([System.IO.FileInfo]$File)
    (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-IncidentClass {
    param([string]$Name)
    if (
        $Name -like 'GIT_DIAGNOSTIC.*' -or
        $Name -like 'FORENSIC_WORKTREE_INVENTORY.*' -or
        $Name -like 'CLEANUP_SAFETY_AUDIT.*' -or
        $Name -like 'WORKTREE_REPAIR_REPORT.*' -or
        $Name -eq 'WORKTREE_LIST_AFTER_REPAIR.txt' -or
        $Name -like 'A3D_DELETE_BLOCKER_*' -or
        $Name -like 'retirement-blocker-*'
    ) { return 'diagnostics' }
    if ($Name -like 'worktree-link-backup-*') { return 'metadata-backups' }
    if ($Name -like 'reorg-preservation-*') { return 'preservation' }
    if ($Name -like 'retirement-*' -or $Name -like 'final-retirement-*') { return 'retirement' }
    return $null
}

function Get-PreservationType {
    param([System.IO.FileInfo]$File)
    $n = $File.Name.ToLowerInvariant()
    if ($n.EndsWith('.bundle')) { return 'GIT_BUNDLE' }
    if ($n.EndsWith('.zip')) { return 'ZIP' }
    if ($n -match 'manifest') { return 'MANIFEST' }
    if ($n -match 'preserv|archive|residue|backup') { return 'PRESERVATION_FILE' }
    return $null
}

$root = Get-NormalizedFullPath $ControlPlaneRoot
$archiveIndex = Join-Path $root 'archive-index'
$archiveRoot = Join-Path $root 'archive'
$incidentRoot = Join-Path $archiveRoot 'incidents\2026-10-13-worktree-recovery'
$targetDirs = [ordered]@{
    diagnostics = Join-Path $incidentRoot 'diagnostics'
    preservation = Join-Path $incidentRoot 'preservation'
    retirement = Join-Path $incidentRoot 'retirement'
    'metadata-backups' = Join-Path $incidentRoot 'metadata-backups'
}
$currentState = Join-Path $root 'CURRENT_STATE.md'
$worktreeHistory = Join-Path $archiveIndex 'WORKTREE_HISTORY.md'
$readmePath = Join-Path $archiveIndex 'README.md'
$catalogPath = Join-Path $archiveIndex 'PRESERVATION_CATALOG.csv'
$ledgerPath = Join-Path $archiveIndex 'RETIREMENT_LEDGER.md'

if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "ControlPlaneRoot does not exist: $root" }
if (-not (Test-Path -LiteralPath $archiveIndex -PathType Container)) { throw "archive-index does not exist: $archiveIndex" }
if (-not (Test-Path -LiteralPath $currentState -PathType Leaf)) { Write-Warning "CURRENT_STATE.md not found: $currentState" }
if (-not (Test-Path -LiteralPath $worktreeHistory -PathType Leaf)) { Write-Warning 'WORKTREE_HISTORY.md not found in archive-index.' }

$inventory = @(Get-ChildItem -LiteralPath $archiveIndex -Force | Sort-Object Name)
Write-Host ''
Write-Host '=== PRE-MOVE INVENTORY: archive-index ==='
foreach ($item in $inventory) {
    $kind = if ($item.PSIsContainer) { 'DIR ' } else { 'FILE' }
    Write-Host ("{0}  {1}" -f $kind,$item.Name)
}

$secretHits = @($inventory | Where-Object { Test-LikelySecretPath $_.FullName })
if ($secretHits.Count -gt 0) {
    Write-Host 'STOP: likely secret material detected in archive-index:' -ForegroundColor Red
    $secretHits | ForEach-Object { Write-Host ("  {0}" -f $_.FullName) -ForegroundColor Red }
    throw 'Likely secrets detected. No archival mutation is permitted.'
}

$plannedMoves = New-Object System.Collections.Generic.List[object]
$manualReview = New-Object System.Collections.Generic.List[object]
$permanentNames = @('README.md','WORKTREE_HISTORY.md','PRESERVATION_CATALOG.csv','RETIREMENT_LEDGER.md')

foreach ($item in $inventory) {
    if ($permanentNames -contains $item.Name) { continue }
    $class = Get-IncidentClass $item.Name
    if ($null -eq $class) {
        $manualReview.Add([pscustomobject]@{Path=$item.FullName;Reason='No unambiguous incident classification rule matched.'})
        continue
    }
    $destination = Join-Path $targetDirs[$class] $item.Name
    if (Test-Path -LiteralPath $destination) {
        $manualReview.Add([pscustomobject]@{Path=$item.FullName;Reason="Destination already exists: $destination"})
        continue
    }
    $plannedMoves.Add([pscustomobject]@{
        Source=$item.FullName
        Destination=$destination
        Class=$class
        ItemType=if ($item.PSIsContainer) {'directory'} else {'file'}
        Sha256=if ($item.PSIsContainer) {$null} else {Get-ItemSha256 $item}
        SizeBytes=if ($item.PSIsContainer) {$null} else {$item.Length}
    })
}

Write-Host ''
Write-Host '=== PLANNED TARGET DIRECTORIES ==='
$targetDirs.Values | ForEach-Object { Write-Host ("CREATE_IF_MISSING  {0}" -f $_) }
Write-Host ''
Write-Host '=== PLANNED MOVES ==='
if ($plannedMoves.Count -eq 0) { Write-Host 'NONE' } else { $plannedMoves | Format-Table Class,ItemType,Source,Destination -AutoSize }
Write-Host ''
Write-Host '=== MANUAL REVIEW ==='
if ($manualReview.Count -eq 0) { Write-Host 'NONE' } else { $manualReview | Format-Table Path,Reason -AutoSize }

$readme = @"
# PREDIKTIA archive-index

archive-index is an index of durable historical evidence. It is not canonical project state.

- Canonical project authority remains prediktia-control-plane/CURRENT_STATE.md.
- Historical forensic, recovery, preservation, and retirement evidence lives under prediktia-control-plane/archive/.
- WORKTREE_HISTORY.md records durable worktree history.
- PRESERVATION_CATALOG.csv inventories preservation artifacts and hashes.
- RETIREMENT_LEDGER.md records only evidence-backed ACTIVE / PROTECTED / RETIRED / UNKNOWN disposition.

Generated by organize_prediktia_archive.ps1.
"@

function Build-PreservationCatalog {
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $archiveRoot -PathType Container)) { return $rows }
    $files = @(Get-ChildItem -LiteralPath $archiveRoot -Recurse -Force -File)
    foreach ($file in $files) {
        if (Test-LikelySecretPath $file.FullName) { throw "Likely secret detected while scanning archive: $($file.FullName)" }
        $type = Get-PreservationType $file
        if ($null -eq $type) { continue }
        $relative = Get-RelativePathSafe -Base $root -Path $file.FullName
        $sourceIncident = if ($relative -like 'archive\incidents\2026-10-13-worktree-recovery\*') {'2026-10-13-worktree-recovery'} else {'UNKNOWN'}
        $rows.Add([pscustomobject]@{
            TYPE=$type
            ARTIFACT=$file.Name
            SOURCE_INCIDENT=$sourceIncident
            SHA256=Get-ItemSha256 $file
            SIZE_BYTES=$file.Length
            PATH=$relative
            CREATED_OR_DISCOVERED_AT=$file.LastWriteTimeUtc.ToString('o')
        })
    }
    return $rows
}

function Build-RetirementLedger {
    param([object[]]$RetirementEvidence)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# PREDIKTIA Retirement Ledger')
    $lines.Add('')
    $lines.Add('This ledger is evidence-based. UNKNOWN is preferred over inference.')
    $lines.Add('')
    $lines.Add('| Repository / Worktree | Status | Evidence |')
    $lines.Add('|---|---|---|')
    $lines.Add('| prediktia | ACTIVE | Canonical active product repository by current organizational directive. |')
    $lines.Add('| prediktia-it-support | ACTIVE | Active IT/support repository by current organizational directive. |')
    $lines.Add('| prediktia-integration | PROTECTED | Unresolved historical merge/working state; explicitly protected pending separate disposition. |')
    foreach ($ev in ($RetirementEvidence | Sort-Object Source)) {
        $name = [System.IO.Path]::GetFileName($ev.Source)
        $lines.Add("| historical evidence: $name | UNKNOWN | Retirement artifact exists, but no specific worktree is inferred RETIRED without structured verified evidence. |")
    }
    $lines -join [Environment]::NewLine
}

$retirementEvidence = @($plannedMoves | Where-Object {$_.Class -eq 'retirement'})
$ledger = Build-RetirementLedger -RetirementEvidence $retirementEvidence

Write-Host ''
Write-Host '=== GENERATED/UPDATED INDEX FILES ==='
Write-Host ("README                 {0}" -f $readmePath)
Write-Host ("PRESERVATION_CATALOG   {0}" -f $catalogPath)
Write-Host ("RETIREMENT_LEDGER      {0}" -f $ledgerPath)

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY_RUN_RESULT: PASS'
    Write-Host ("FILES_PLANNED_TO_MOVE: {0}" -f $plannedMoves.Count)
    Write-Host ("FILES_LEFT_FOR_MANUAL_REVIEW: {0}" -f $manualReview.Count)
    Write-Host 'MUTATION_PERFORMED: NO'
    Write-Host 'Re-run with -Apply ONLY after explicit approval.'
    exit 0
}

Write-Host ''
Write-Host '=== APPLY MODE: EXACT PLAN ABOVE WILL NOW BE APPLIED ===' -ForegroundColor Yellow
foreach ($dir in $targetDirs.Values) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$manifestPath = Join-Path $incidentRoot ('pre-move-manifest-{0}.csv' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
$plannedMoves | Select-Object Source,Destination,Class,ItemType,Sha256,SizeBytes | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

foreach ($move in $plannedMoves) {
    if (Test-LikelySecretPath $move.Source) { throw "STOP before move: likely secret detected: $($move.Source)" }
    if (Test-Path -LiteralPath $move.Destination) { throw "STOP before move: destination appeared after planning: $($move.Destination)" }
    Move-Item -LiteralPath $move.Source -Destination $move.Destination
    if ($move.ItemType -eq 'file') {
        $after = (Get-FileHash -LiteralPath $move.Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($after -ne $move.Sha256) { throw "Hash verification failed after move: $($move.Destination)" }
    }
}

Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8
$catalog = @(Build-PreservationCatalog)
$catalog | Export-Csv -LiteralPath $catalogPath -NoTypeInformation -Encoding UTF8
$ledger = Build-RetirementLedger -RetirementEvidence $retirementEvidence
Set-Content -LiteralPath $ledgerPath -Value $ledger -Encoding UTF8

Write-Host ''
Write-Host 'APPLY_RESULT: PASS'
Write-Host ("PRE_MOVE_MANIFEST: {0}" -f $manifestPath)
Write-Host ("FILES_MOVED: {0}" -f $plannedMoves.Count)
Write-Host ("FILES_LEFT_FOR_MANUAL_REVIEW: {0}" -f $manualReview.Count)
Write-Host 'DELETIONS_PERFORMED: 0'
