param(
    [string]$OutputDir = (Join-Path $HOME ".prediktia-it\workspace")
)

$ErrorActionPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$hostName = $env:COMPUTERNAME
$reportPath = Join-Path $OutputDir ("prod-runtime-inventory-" + $hostName + ".txt")
$lines = [System.Collections.Generic.List[string]]::new()

function Add-Line([string]$Text = "") {
    $lines.Add($Text)
}

function Tag-Text([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $tags = [System.Collections.Generic.List[string]]::new()
    $patterns = [ordered]@{
        PREDIKTIA = "prediktia"
        LIVE_SYNC = "live_sync"
        HISTORY_BACKFILL = "history_backfill"
        OPS_TICK = "ops_tick"
        STATISTICS_RECONCILE = "statistics_reconcile"
        STATISTICS_BACKFILL = "statistics_backfill"
        UVICORN = "uvicorn"
        FASTAPI_APP = "app\.main"
        PYTHON = "python"
        DOCKER = "docker"
        WSL = "wsl"
    }
    foreach ($kv in $patterns.GetEnumerator()) {
        if ($Text -match $kv.Value) { $tags.Add($kv.Key) }
    }
    return $tags
}

function Read-DotEnvKeys([string]$Path) {
    $items = @()
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $name = $matches[1]
            $value = $matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                if ($value.Length -ge 2) { $value = $value.Substring(1, $value.Length - 2) }
            }
            $items += [pscustomobject]@{
                Name = $name
                NonEmpty = -not [string]::IsNullOrWhiteSpace($value)
                Value = $value
            }
        }
    }
    return $items
}

function Capability-ForKey([string]$Name) {
    if ($Name -match 'DATABASE_URL$') {
        if ($Name -match '^(TEST_|DI_A6_|.*REHEARSAL.*|.*G2.*)') { return "NON_PRODUCTION_DB" }
        return "DATABASE_WRITE_CANDIDATE"
    }
    if ($Name -in @("API_FOOTBALL_KEY","FIVE_DOLLAR_FOOTBALL_API_KEY","FIVE_DOLLAR_FOOTBALL_KEY")) {
        return "PROVIDER_API"
    }
    if ($Name -eq "PREDIKTIA_EXPECTED_DB_TARGET") { return "DB_TARGET_GUARD" }
    if ($Name -eq "SYNC_ENDPOINTS_ENABLED") { return "API_SYNC_CONTROL" }
    if ($Name -eq "PREDIKTIA_SCHEDULER_ENABLED") { return "SCHEDULER_CONTROL" }
    return "OTHER"
}

function Find-PrediktiaDirs {
    $roots = @(
        (Join-Path $HOME "Desktop"),
        (Join-Path $HOME "OneDrive\Desktop"),
        (Join-Path $HOME "OneDrive\Escritorio"),
        (Join-Path $HOME "Documents"),
        (Join-Path $HOME "OneDrive\Documents")
    ) | Where-Object { Test-Path $_ } | Select-Object -Unique

    $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $roots) {
        if ((Split-Path $root -Leaf) -match '(?i)prediktia') { [void]$found.Add($root) }
        Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^prediktia' } |
            ForEach-Object { [void]$found.Add($_.FullName) }
    }
    return @($found)
}

Add-Line "PREDIKTIA_PRODUCTION_RUNTIME_INVENTORY_V1"
Add-Line ("HOST_ID=" + $hostName)
Add-Line ("HOSTNAME=" + $hostName)
Add-Line ("USER=" + $env:USERNAME)
$os = Get-CimInstance Win32_OperatingSystem
if ($os) {
    Add-Line ("OS=" + $os.Caption + " " + $os.Version)
}
Add-Line ("TIMESTAMP_UTC=" + [DateTime]::UtcNow.ToString("o"))
Add-Line ""

$repoDirs = @(Find-PrediktiaDirs)
Add-Line "=== REPOSITORIES / PREDIKTIA DIRECTORIES ==="
if ($repoDirs.Count -eq 0) {
    Add-Line "PREDIKTIA_REPOS_PRESENT=NONE_FOUND"
} else {
    foreach ($dir in $repoDirs | Sort-Object) {
        $isGit = Test-Path (Join-Path $dir ".git")
        $remote = ""
        $branch = ""
        if ($isGit -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $remote = (& git -C $dir remote get-url origin 2>$null)
            $branch = (& git -C $dir branch --show-current 2>$null)
        }
        Add-Line ("DIR=" + $dir)
        Add-Line ("  IS_GIT_REPO=" + $(if ($isGit) {"YES"} else {"NO"}))
        if ($remote) { Add-Line ("  REMOTE=" + $remote) }
        if ($branch) { Add-Line ("  BRANCH=" + $branch) }
    }
}
Add-Line ""

Add-Line "=== ENV / CREDENTIAL SURFACES (NAMES ONLY) ==="
$envFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($dir in $repoDirs) {
    Get-ChildItem -LiteralPath $dir -File -Force -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ".env" -or $_.Name -like "*.env" -or $_.Name -like ".env.*" } |
        ForEach-Object { [void]$envFiles.Add($_.FullName) }
}
$secretDir = Join-Path $HOME ".prediktia-secrets"
if (Test-Path $secretDir) {
    Get-ChildItem -LiteralPath $secretDir -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$envFiles.Add($_.FullName) }
}

$hasDbCandidate = $false
$hasProvider = $false
foreach ($file in @($envFiles) | Sort-Object) {
    $vars = @(Read-DotEnvKeys $file)
    if ($vars.Count -eq 0) { continue }

    $interesting = @($vars | Where-Object {
        $_.Name -match 'DATABASE_URL$' -or
        $_.Name -in @("API_FOOTBALL_KEY","FIVE_DOLLAR_FOOTBALL_API_KEY","FIVE_DOLLAR_FOOTBALL_KEY",
                      "PREDIKTIA_EXPECTED_DB_TARGET","SYNC_ENDPOINTS_ENABLED","PREDIKTIA_SCHEDULER_ENABLED")
    })
    if ($interesting.Count -eq 0) { continue }

    Add-Line ("FILE=" + $file)
    foreach ($v in $interesting) {
        $cap = Capability-ForKey $v.Name
        if ($cap -eq "DATABASE_WRITE_CANDIDATE" -and $v.NonEmpty) { $hasDbCandidate = $true }
        if ($cap -eq "PROVIDER_API" -and $v.NonEmpty) { $hasProvider = $true }

        if ($v.Name -in @("SYNC_ENDPOINTS_ENABLED","PREDIKTIA_SCHEDULER_ENABLED")) {
            $state = if (-not $v.NonEmpty) { "UNSET_OR_EMPTY" } elseif ($v.Value.ToLowerInvariant() -eq "true") { "TRUE" } else { "NOT_TRUE" }
            Add-Line ("  " + $v.Name + " | CAPABILITY=" + $cap + " | STATE=" + $state)
        } else {
            Add-Line ("  " + $v.Name + " | CAPABILITY=" + $cap + " | NONEMPTY=" + $(if ($v.NonEmpty) {"YES"} else {"NO"}))
        }
    }
}
if ($envFiles.Count -eq 0) { Add-Line "ENV_FILES=NONE_FOUND" }
Add-Line ("HAS_DATABASE_WRITE_CANDIDATE=" + $(if ($hasDbCandidate) {"YES"} else {"NO"}))
Add-Line ("HAS_PROVIDER_CREDENTIALS=" + $(if ($hasProvider) {"YES"} else {"NO"}))
Add-Line ""

Add-Line "=== RUNNING PROCESSES ==="
$allProc = @(Get-CimInstance Win32_Process)
$pythonCount = @($allProc | Where-Object { $_.Name -match '(?i)^python(w)?\.exe$|^uvicorn\.exe$' }).Count
Add-Line ("PYTHON_UVICORN_PROCESS_COUNT=" + $pythonCount)
$relevantProc = @()
foreach ($p in $allProc) {
    $probe = (($p.Name + " " + $p.CommandLine) -as [string])
    $tags = @(Tag-Text $probe)
    if ($tags -contains "PREDIKTIA" -or $tags -contains "LIVE_SYNC" -or
        $tags -contains "HISTORY_BACKFILL" -or $tags -contains "OPS_TICK" -or
        $tags -contains "STATISTICS_RECONCILE" -or $tags -contains "STATISTICS_BACKFILL" -or
        $tags -contains "UVICORN" -or $tags -contains "FASTAPI_APP") {
        $relevantProc += [pscustomobject]@{ Name=$p.Name; PID=$p.ProcessId; Tags=($tags -join ",") }
    }
}
if ($relevantProc.Count -eq 0) {
    Add-Line "RUNNING_PREDIKTIA_PROCESSES=NONE_FOUND"
} else {
    foreach ($p in $relevantProc) {
        Add-Line ("PROCESS=" + $p.Name + " PID=" + $p.PID + " TAGS=" + $p.Tags)
    }
}
Add-Line ""

Add-Line "=== WINDOWS TASK SCHEDULER ==="
$taskHits = @()
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    foreach ($task in (Get-ScheduledTask)) {
        $probe = $task.TaskName + " " + $task.TaskPath
        foreach ($a in $task.Actions) { $probe += " " + $a.Execute + " " + $a.Arguments }
        $tags = @(Tag-Text $probe)
        if ($tags -contains "PREDIKTIA" -or $tags -contains "LIVE_SYNC" -or
            $tags -contains "HISTORY_BACKFILL" -or $tags -contains "OPS_TICK" -or
            $tags -contains "UVICORN" -or $tags -contains "FASTAPI_APP") {
            $taskHits += [pscustomobject]@{Name=$task.TaskName;Path=$task.TaskPath;State=$task.State;Tags=($tags -join ",")}
        }
    }
}
if ($taskHits.Count -eq 0) {
    Add-Line "WINDOWS_TASK_SCHEDULER_ENTRIES=NONE_FOUND"
} else {
    foreach ($t in $taskHits) {
        Add-Line ("TASK=" + $t.Path + $t.Name + " STATE=" + $t.State + " TAGS=" + $t.Tags)
    }
}
Add-Line ""

Add-Line "=== WINDOWS SERVICES ==="
$serviceHits = @()
foreach ($s in (Get-CimInstance Win32_Service)) {
    $probe = $s.Name + " " + $s.DisplayName + " " + $s.PathName
    $tags = @(Tag-Text $probe)
    if ($tags -contains "PREDIKTIA" -or $tags -contains "LIVE_SYNC" -or
        $tags -contains "HISTORY_BACKFILL" -or $tags -contains "OPS_TICK" -or
        $tags -contains "UVICORN" -or $tags -contains "FASTAPI_APP") {
        $serviceHits += [pscustomobject]@{Name=$s.Name;State=$s.State;StartMode=$s.StartMode;Tags=($tags -join ",")}
    }
}
if ($serviceHits.Count -eq 0) {
    Add-Line "SERVICES=NONE_FOUND"
} else {
    foreach ($s in $serviceHits) {
        Add-Line ("SERVICE=" + $s.Name + " STATE=" + $s.State + " STARTMODE=" + $s.StartMode + " TAGS=" + $s.Tags)
    }
}
Add-Line ""

Add-Line "=== STARTUP / AUTOSTART ==="
$startupHits = @()
$runKeys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($rk in $runKeys) {
    if (-not (Test-Path $rk)) { continue }
    $props = Get-ItemProperty -Path $rk
    foreach ($prop in $props.PSObject.Properties) {
        if ($prop.Name -match '^PS') { continue }
        $probe = $prop.Name + " " + [string]$prop.Value
        $tags = @(Tag-Text $probe)
        if ($tags -contains "PREDIKTIA" -or $tags -contains "LIVE_SYNC" -or
            $tags -contains "HISTORY_BACKFILL" -or $tags -contains "OPS_TICK" -or
            $tags -contains "UVICORN" -or $tags -contains "FASTAPI_APP") {
            $startupHits += [pscustomobject]@{Source=$rk;Name=$prop.Name;Tags=($tags -join ",")}
        }
    }
}
$startupDirs = @(
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp")
)
foreach ($sd in $startupDirs) {
    if (-not (Test-Path $sd)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $sd -Force)) {
        $tags = @(Tag-Text ($f.Name + " " + $f.FullName))
        if ($tags -contains "PREDIKTIA" -or $tags -contains "UVICORN") {
            $startupHits += [pscustomobject]@{Source=$sd;Name=$f.Name;Tags=($tags -join ",")}
        }
    }
}
if ($startupHits.Count -eq 0) {
    Add-Line "STARTUP_AUTOSTART=NONE_FOUND"
} else {
    foreach ($x in $startupHits) {
        Add-Line ("STARTUP=" + $x.Name + " SOURCE=" + $x.Source + " TAGS=" + $x.Tags)
    }
}
Add-Line ""

Add-Line "=== DOCKER ==="
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerRows = @(& docker ps --format "{{.ID}}|{{.Image}}|{{.Names}}|{{.Status}}" 2>$null)
    $dockerHits = @($dockerRows | Where-Object { $_ -match '(?i)prediktia|python|uvicorn' })
    if ($dockerHits.Count -eq 0) {
        Add-Line "RELEVANT_CONTAINERS=NONE_RUNNING"
    } else {
        foreach ($row in $dockerHits) { Add-Line ("CONTAINER=" + $row) }
    }
} else {
    Add-Line "DOCKER=NOT_INSTALLED_OR_NOT_IN_PATH"
}
Add-Line ""

Add-Line "=== WSL ==="
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $distros = @(& wsl.exe -l -q 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($distros.Count -eq 0) {
        Add-Line "WSL_DISTROS=NONE"
    } else {
        foreach ($d in $distros) {
            $cleanD = $d.Trim([char]0).Trim()
            Add-Line ("WSL_DISTRO=" + $cleanD)
            $psRaw = @(& wsl.exe -d $cleanD -- sh -lc 'ps -eo pid=,comm=,args=' 2>$null)
            $psHits = @($psRaw | Where-Object { $_ -match '(?i)prediktia|live_sync|history_backfill|ops_tick|uvicorn|app\.main' })
            Add-Line ("  RELEVANT_PROCESS_COUNT=" + $psHits.Count)
            foreach ($row in $psHits) {
                $tags = @(Tag-Text $row)
                Add-Line ("  PROCESS_TAGS=" + ($tags -join ","))
            }
            $cronRaw = @(& wsl.exe -d $cleanD -- sh -lc 'crontab -l 2>/dev/null || true' 2>$null)
            $cronHits = @($cronRaw | Where-Object { $_ -match '(?i)prediktia|live_sync|history_backfill|ops_tick|uvicorn|app\.main' })
            Add-Line ("  RELEVANT_CRON_COUNT=" + $cronHits.Count)
            foreach ($row in $cronHits) {
                $tags = @(Tag-Text $row)
                Add-Line ("  CRON_TAGS=" + ($tags -join ","))
            }
        }
    }
} else {
    Add-Line "WSL=NOT_AVAILABLE"
}
Add-Line ""

$pythonAvailable = [bool](Get-Command python -ErrorAction SilentlyContinue)
$manualCapability = ($repoDirs.Count -gt 0 -and $pythonAvailable -and $hasDbCandidate)
Add-Line "=== SUMMARY ==="
Add-Line ("HAS_PRODUCTION_DATABASE_CREDENTIAL=REQUIRES_TARGET_CLASSIFICATION")
Add-Line ("HAS_DATABASE_WRITE_CANDIDATE=" + $(if ($hasDbCandidate) {"YES"} else {"NO"}))
Add-Line ("HAS_PROVIDER_CREDENTIALS=" + $(if ($hasProvider) {"YES"} else {"NO"}))
Add-Line ("MANUAL_CLI_CAPABILITY=" + $(if ($manualCapability) {"YES"} else {"NO"}))
Add-Line ("RELEVANT_RUNNING_PROCESS_COUNT=" + $relevantProc.Count)
Add-Line ("RELEVANT_SCHEDULED_TASK_COUNT=" + $taskHits.Count)
Add-Line ("RELEVANT_SERVICE_COUNT=" + $serviceHits.Count)
Add-Line ("RELEVANT_STARTUP_COUNT=" + $startupHits.Count)
Add-Line "SECRET_VALUES_PRINTED=NO"
Add-Line "SYSTEM_MUTATION=NO"
Add-Line "APPLICATION_MUTATION=NO"
Add-Line "DATABASE_MUTATION=NO"

$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
$lines
Write-Output ("REPORT_FILE=" + $reportPath)
