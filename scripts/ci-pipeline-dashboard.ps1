#requires -Version 5.1

<#
.SYNOPSIS
Shows a live, split-screen dashboard for GitHub PR workers and Windows health.

.DESCRIPTION
The left two-thirds shows open pull requests grouped by repository and target
branch, their checks, tester APK releases, and recent assistant commentary from
a Codex task transcript. The right third shows per-core CPU load, memory and
commit pressure, and the busiest processes.

The script only reads GitHub and local system state. It honors GH_CONFIG_DIR,
so an existing temporary or isolated gh login continues to work.

.EXAMPLE
./scripts/ci-pipeline-dashboard.ps1

.EXAMPLE
./scripts/ci-pipeline-dashboard.ps1 -Repository electrobrian/japanglify,brianreborn/japanglify -IntervalSeconds 3

.EXAMPLE
./scripts/ci-pipeline-dashboard.ps1 -Once -TranscriptLines 3

.EXAMPLE
./scripts/ci-pipeline-dashboard.ps1 -OutputFormat Json

Emits one compact JSON object per line for a future Node/SSE/WebSocket bridge.
#>

[CmdletBinding()]
param(
    [string[]] $Repository = @('electrobrian/japanglify'),
    [ValidateRange(1, 300)]
    [int] $IntervalSeconds = 5,
    [ValidateRange(5, 3600)]
    [int] $ReleaseRefreshSeconds = 30,
    [string] $TranscriptPath,
    [ValidateRange(0, 20)]
    [int] $TranscriptLines = 6,
    [ValidateRange(5, 10080)]
    [int] $WorkerLookbackMinutes = 240,
    [ValidateRange(1, 100)]
    [int] $MaxWorkers = 24,
    [ValidateSet('Console', 'Json')]
    [string] $OutputFormat = 'Console',
    [switch] $Once
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-GhJson {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Arguments -join ' ') failed: $($output -join ' ')"
    }
    $text = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text | ConvertFrom-Json)
}

function Get-TerminalWidth {
    try { return [Math]::Max(80, [Console]::WindowWidth) } catch { return 120 }
}

function Limit-Text {
    param([AllowNull()][string] $Text, [int] $Width)
    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { $Text = '' }
    $Text = $Text -replace '\s+', ' '
    if ($Text.Length -le $Width) { return $Text }
    if ($Width -le 3) { return $Text.Substring(0, $Width) }
    return $Text.Substring(0, $Width - 3) + '...'
}

function Pad-Line {
    param([AllowNull()][string] $Text, [int] $Width)
    $value = Limit-Text $Text $Width
    return $value.PadRight($Width)
}

function Format-Age {
    param([AllowNull()] $Timestamp)
    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) { return 'unknown' }
    try {
        $parsed = if ($Timestamp -is [DateTime]) { [DateTimeOffset]$Timestamp } else { [DateTimeOffset]::Parse([string]$Timestamp) }
        $age = [DateTimeOffset]::Now - $parsed
        if ($age.TotalSeconds -lt 90) { return "$([Math]::Max(0, [int]$age.TotalSeconds))s ago" }
        if ($age.TotalMinutes -lt 90) { return "$([int]$age.TotalMinutes)m ago" }
        if ($age.TotalHours -lt 48) { return "$([int]$age.TotalHours)h ago" }
        return "$([int]$age.TotalDays)d ago"
    } catch { return 'unknown' }
}

function Format-DurationSeconds {
    param([AllowNull()] $Seconds)
    if ($null -eq $Seconds) { return 'unknown' }
    $value = [Math]::Max(0, [double]$Seconds)
    $span = [TimeSpan]::FromSeconds($value)
    if ($span.TotalDays -ge 1) { return "$([int]$span.TotalDays)d $($span.Hours)h" }
    if ($span.TotalHours -ge 1) { return "$([int]$span.TotalHours)h $($span.Minutes)m" }
    if ($span.TotalMinutes -ge 1) { return "$([int]$span.TotalMinutes)m $($span.Seconds)s" }
    return "$([int]$span.TotalSeconds)s"
}

function Get-CheckState {
    param($Checks)
    $items = @($Checks)
    if ($items.Count -eq 0) { return 'WAIT' }
    $bad = @('FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'STALE')
    if (@($items | Where-Object { $_.conclusion -in $bad }).Count -gt 0) { return 'FAIL' }
    if (@($items | Where-Object { $_.status -ne 'COMPLETED' }).Count -gt 0) { return 'RUN ' }
    if (@($items | Where-Object { $_.conclusion -in @('SUCCESS', 'NEUTRAL', 'SKIPPED') }).Count -eq $items.Count) { return 'PASS' }
    return 'WAIT'
}

function Get-CheckLabel {
    param($Check)
    $state = Get-CheckState @($Check)
    $name = if ($Check.workflowName) { "$($Check.workflowName) / $($Check.name)" } else { [string]$Check.name }
    $duration = ''
    try {
        if ($Check.startedAt) {
            $end = if ($Check.completedAt) { [DateTimeOffset]::Parse($Check.completedAt) } else { [DateTimeOffset]::Now }
            $elapsed = $end - [DateTimeOffset]::Parse($Check.startedAt)
            $duration = if ($elapsed.TotalMinutes -ge 1) { " $([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s" } else { " $([int]$elapsed.TotalSeconds)s" }
        }
    } catch {}
    return "[$state] $name$duration"
}

function Get-OpenPullRequests {
    param([string[]] $Repositories)
    $all = @()
    foreach ($repo in $Repositories) {
        $prs = Invoke-GhJson @(
            'pr', 'list', '--repo', $repo, '--state', 'open', '--limit', '100',
            '--json', 'number,title,url,headRefName,baseRefName,isDraft,mergeStateStatus,statusCheckRollup,createdAt,updatedAt,author'
        )
        foreach ($pr in $prs) {
            $all += [pscustomobject]@{ Repository = $repo; PullRequest = $pr }
        }
    }
    return @($all)
}

function Get-TesterReleases {
    param([string[]] $Repositories)
    $map = @{}
    foreach ($repo in $Repositories) {
        $releases = Invoke-GhJson @('api', "repos/$repo/releases?per_page=100")
        foreach ($release in $releases) {
            if ($release.tag_name -match '^pr-(\d+)-build-(\d+)$') {
                $key = "$repo#$($Matches[1])"
                $build = [int]$Matches[2]
                if (-not $map.ContainsKey($key) -or $build -gt $map[$key].Build) {
                    $map[$key] = [pscustomobject]@{
                        Build = $build
                        Tag = [string]$release.tag_name
                        Url = [string]$release.html_url
                        Assets = @($release.assets | Where-Object { $_.name -like '*.apk' })
                    }
                }
            }
        }
    }
    return $map
}

function Find-LatestTranscript {
    $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot)) { return $null }
    return Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-TailLines {
    param([Parameter(Mandatory)][string] $Path, [int] $Count = 800, [int] $MaxBytes = 1048576)
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $start = [Math]::Max(0, $stream.Length - $MaxBytes)
        $null = $stream.Seek($start, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream)
        $text = $reader.ReadToEnd()
        $lines = @($text -split "`r?`n")
        if ($start -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }
        return @($lines | Where-Object { $_.Length -gt 0 } | Select-Object -Last $Count)
    } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}

function Get-TranscriptCommentary {
    param([AllowNull()][string] $Path, [int] $Count)
    if ($Count -eq 0 -or [string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return @() }
    $messages = @()
    foreach ($line in @(Get-TailLines -Path $Path -Count 800)) {
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -ne 'response_item' -or $entry.payload.type -ne 'message' -or $entry.payload.role -ne 'assistant') { continue }
            foreach ($part in @($entry.payload.content)) {
                if ($part.type -eq 'output_text' -and -not [string]::IsNullOrWhiteSpace($part.text)) {
                    $messages += [pscustomobject]@{ Timestamp = [string]$entry.timestamp; Text = ([string]$part.text -replace '\s+', ' ').Trim() }
                }
            }
        } catch {}
    }
    return @($messages | Select-Object -Last $Count)
}

function Get-CodexWorkers {
    param([AllowNull()][string] $CurrentTranscript, [int] $LookbackMinutes, [int] $Limit)
    $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot)) { return @() }
    $cutoff = (Get-Date).AddMinutes(-$LookbackMinutes)
    $workers = @()
    $files = @(Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First ($Limit * 3))
    foreach ($file in $files) {
        try {
            $meta = (Get-Content -LiteralPath $file.FullName -First 1) | ConvertFrom-Json
            if ($meta.type -ne 'session_meta') { continue }
            $tail = @(Get-TailLines -Path $file.FullName -Count 800)
            $referenceText = $tail -join [Environment]::NewLine
            $prNumbers = @([regex]::Matches($referenceText, '(?i)(?:\bPR\s*#\s*|\bpull request\s+#?\s*)(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
            $issueNumbers = @([regex]::Matches($referenceText, '(?i)\bissue\s*#\s*(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
            $isCurrent = $CurrentTranscript -and $file.FullName -eq $CurrentTranscript
            if ($isCurrent) { $prNumbers = @(); $issueNumbers = @() }
            $agentPathProperty = $meta.payload.PSObject.Properties['agent_path']
            $agentPath = if ($agentPathProperty) { [string]$agentPathProperty.Value } else { $null }
            $isSubagent = -not [string]::IsNullOrWhiteSpace($agentPath)
            if ($agentPath -match '(?i)(?:^|/)pr(\d+)[_-]') { $prNumbers = @([int]$Matches[1]) }
            if ($agentPath -match '(?i)(?:^|/)issue(\d+)[_-]') { $issueNumbers = @($issueNumbers + [int]$Matches[1] | Sort-Object -Unique) }
            if (-not $isCurrent -and -not $isSubagent -and $prNumbers.Count -eq 0 -and $issueNumbers.Count -eq 0) { continue }
            $messages = @(Get-TranscriptCommentary $file.FullName 1)
            $latestSummary = if ($messages.Count -gt 0) { [string]($messages[-1].Text) } else { $null }
            $ageSeconds = [Math]::Max(0, ((Get-Date) - $file.LastWriteTime).TotalSeconds)
            $completionTimestamp = $null
            foreach ($line in @($tail | Select-Object -Last 12)) {
                if ($line -notmatch '"type":"task_complete"') { continue }
                try { $completionTimestamp = [string](($line | ConvertFrom-Json).timestamp) } catch {}
            }
            $completed = -not $isCurrent -and -not [string]::IsNullOrWhiteSpace($completionTimestamp)
            $activity = if ($completed) { 'COMPLETE' } elseif ($ageSeconds -lt ($IntervalSeconds * 2.5)) { 'ACTIVE' } elseif ($ageSeconds -lt 600) { 'RECENT' } else { 'IDLE' }
            $outcome = $null
            if ($latestSummary -match '(?im)\bstatus\s*[:=]\s*(healthy|warning|blocked)\b') { $outcome = $Matches[1].ToLowerInvariant() }
            $nicknameProperty = $meta.payload.PSObject.Properties['agent_nickname']
            $nickname = if ($nicknameProperty) { [string]$nicknameProperty.Value } else { $null }
            $shortId = ([string]$meta.payload.id)
            if ($shortId.Length -gt 8) { $shortId = $shortId.Substring($shortId.Length - 8) }
            $role = if ($isCurrent) { 'orchestrator' } elseif ($isSubagent) { 'subagent' } else { 'task' }
            $name = if ($isCurrent) { 'CI orchestrator' } elseif ($nickname) { $nickname } elseif ($prNumbers.Count -eq 1) { "PR #$($prNumbers[0]) worker" } elseif ($issueNumbers.Count -eq 1) { "issue #$($issueNumbers[0]) worker" } else { "$role $shortId" }
            $assignmentRole = if ($isCurrent) { 'control-plane' } elseif ($agentPath -match '(?i)investigat|review|audit') { 'investigator' } else { 'worker' }
            $workerRepository = if ($Repository.Count -gt 0) { [string]$Repository[0] } else { $null }
            $parentProcessIds = @()
            $parentProcessIds += @($prNumbers | ForEach-Object { "pr:$workerRepository#$_" })
            $parentProcessIds += @($issueNumbers | ForEach-Object { "issue:$workerRepository#$_" })
            $startedAt = [string]$meta.payload.timestamp
            $runtimeEnd = if ($completed) { [DateTimeOffset]::Parse($completionTimestamp) } else { [DateTimeOffset]::Now }
            $runtimeSeconds = try { [Math]::Max(0, ($runtimeEnd - [DateTimeOffset]::Parse($startedAt)).TotalSeconds) } catch { $null }
            $workers += [pscustomobject]@{
                ThreadId = [string]$meta.payload.id
                Name = $name
                Role = $role
                Host = [Environment]::MachineName
                Provider = [string]$meta.payload.model_provider
                Model = $null
                ReasoningEffort = $null
                ModelApprovalState = if ($isCurrent) { 'not-applicable' } else { 'historical-unrecorded' }
                ModelApprovedBy = $null
                ModelApprovedAt = $null
                Transport = 'local-transcript'
                Repository = $workerRepository
                AssignmentRole = $assignmentRole
                ParentProcessIds = @($parentProcessIds)
                ProcessIds = @()
                Activity = $activity
                Outcome = $outcome
                StartedAt = $startedAt
                CompletedAt = $completionTimestamp
                RuntimeSeconds = $runtimeSeconds
                LastActivityAt = ([DateTimeOffset]$file.LastWriteTime).ToString('o')
                PullRequests = @($prNumbers)
                Issues = @($issueNumbers)
                Summary = $latestSummary
                TranscriptPath = $file.FullName
            }
        } catch {}
        if ($workers.Count -ge $Limit) { break }
    }
    return @($workers)
}

function New-Bar {
    param([double] $Percent, [int] $Width)
    $bounded = [Math]::Max(0, [Math]::Min(100, $Percent))
    $filled = [int][Math]::Round($bounded * $Width / 100)
    return ('#' * $filled) + ('-' * ($Width - $filled))
}

function Get-PowerSnapshot {
    $errors = @()
    $plan = $null
    $lineStatus = $null
    $batteryPercent = $null
    $batteryStatus = $null
    $batteryLifeRemainingSeconds = $null
    $performancePercent = $null
    $maximumFrequencyPercent = $null
    $performanceLimitPercent = $null
    $frequencyMhz = $null
    try {
        $powerPlanText = @(& powercfg /getactivescheme 2>&1) -join ' '
        if ($LASTEXITCODE -eq 0 -and $powerPlanText -match '\(([^)]+)\)') { $plan = $Matches[1] }
    } catch { $errors += "Power plan unavailable: $($_.Exception.Message)" }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $status = [System.Windows.Forms.SystemInformation]::PowerStatus
        $lineStatus = [string]$status.PowerLineStatus
        if ([double]$status.BatteryLifePercent -ge 0) { $batteryPercent = [Math]::Round(100 * [double]$status.BatteryLifePercent, 0) }
        $batteryStatus = [string]$status.BatteryChargeStatus
        if ([int]$status.BatteryLifeRemaining -ge 0) { $batteryLifeRemainingSeconds = [int]$status.BatteryLifeRemaining }
    } catch { $errors += "Battery state unavailable: $($_.Exception.Message)" }
    try {
        $counterPaths = @(
            '\Processor Information(_Total)\% Processor Performance'
            '\Processor Information(_Total)\% of Maximum Frequency'
            '\Processor Information(_Total)\% Performance Limit'
            '\Processor Information(_Total)\Processor Frequency'
        )
        $samples = @((Get-Counter -Counter $counterPaths).CounterSamples)
        $performancePercent = [Math]::Round([double](($samples | Where-Object { $_.Path -like '*\% processor performance' } | Select-Object -First 1).CookedValue), 1)
        $maximumFrequencyPercent = [Math]::Round([double](($samples | Where-Object { $_.Path -like '*\% of maximum frequency' } | Select-Object -First 1).CookedValue), 1)
        $performanceLimitPercent = [Math]::Round([double](($samples | Where-Object { $_.Path -like '*\% performance limit' } | Select-Object -First 1).CookedValue), 1)
        $frequencyMhz = [Math]::Round([double](($samples | Where-Object { $_.Path -like '*\processor frequency' } | Select-Object -First 1).CookedValue), 0)
    } catch { $errors += "Processor power counters unavailable: $($_.Exception.Message)" }

    $throttlednessPercent = if ($null -ne $performanceLimitPercent) { [Math]::Max(0, [Math]::Min(100, 100 - $performanceLimitPercent)) } else { $null }
    $state = 'unknown'
    if ($null -ne $performanceLimitPercent -and $performanceLimitPercent -lt 90) {
        $state = 'throttled'
    } elseif ($lineStatus -eq 'Offline' -or ($plan -and $plan -match '(?i)saver|eco|efficien')) {
        $state = 'power-saving'
    } elseif ($null -ne $performanceLimitPercent) {
        $state = 'unrestricted'
    }
    return [pscustomobject]@{
        Platform = 'windows'
        Scope = 'host'
        Source = 'windows-native'
        Confidence = if ($errors.Count -eq 0) { 'high' } else { 'partial' }
        State = $state
        ThrottlednessPercent = $throttlednessPercent
        ActivePlan = $plan
        PowerLineStatus = $lineStatus
        BatteryPercent = $batteryPercent
        BatteryStatus = $batteryStatus
        BatteryLifeRemainingSeconds = $batteryLifeRemainingSeconds
        ProcessorPerformancePercent = $performancePercent
        MaximumFrequencyPercent = $maximumFrequencyPercent
        PerformanceLimitPercent = $performanceLimitPercent
        FrequencyMhz = $frequencyMhz
        Errors = @($errors)
    }
}

function Get-SystemSnapshot {
    param([DateTimeOffset] $DashboardStartedAt)
    $errors = @()
    $systemUptimeSeconds = $null
    try { $systemUptimeSeconds = [Math]::Round([double]((Get-Counter '\System\System Up Time').CounterSamples | Select-Object -First 1).CookedValue, 1) } catch { $errors += "System uptime unavailable: $($_.Exception.Message)" }
    $cpuTotal = $null
    $cpuCores = @()
    try {
        $cpuSamples = @((Get-Counter '\Processor(*)\% Processor Time').CounterSamples)
        $processors = @($cpuSamples |
            Where-Object { $_.InstanceName -ne '_total' } |
            Sort-Object { if ($_.InstanceName -match '^\d+$') { [int]$_.InstanceName } else { [int]::MaxValue } })
        $totalProcessor = $cpuSamples | Where-Object { $_.InstanceName -eq '_total' } | Select-Object -First 1
        if ($totalProcessor) {
            $cpuTotal = [Math]::Round([double]$totalProcessor.CookedValue, 1)
        }
        foreach ($cpu in $processors) {
            $cpuCores += [pscustomobject]@{ Core = [string]$cpu.InstanceName; Percent = [Math]::Round([double]$cpu.CookedValue, 1) }
        }
    } catch {
        $errors += "CPU counters unavailable: $($_.Exception.Message)"
    }

    $memorySnapshot = $null
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $computer = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        $physicalTotalMb = [double]$computer.TotalPhysicalMemory / 1MB
        $memorySamples = @((Get-Counter '\Memory\Available MBytes','\Memory\Committed Bytes','\Memory\Commit Limit','\Memory\Pages/sec').CounterSamples)
        $availableMb = [double](($memorySamples | Where-Object { $_.Path -like '*\available mbytes' } | Select-Object -First 1).CookedValue)
        $physicalUsedMb = $physicalTotalMb - $availableMb
        $physicalPercent = if ($physicalTotalMb -gt 0) { 100 * $physicalUsedMb / $physicalTotalMb } else { 0 }
        $commitMb = [double](($memorySamples | Where-Object { $_.Path -like '*\committed bytes' } | Select-Object -First 1).CookedValue) / 1MB
        $commitLimitMb = [double](($memorySamples | Where-Object { $_.Path -like '*\commit limit' } | Select-Object -First 1).CookedValue) / 1MB
        $pagesPerSecond = [double](($memorySamples | Where-Object { $_.Path -like '*\pages/sec' } | Select-Object -First 1).CookedValue)
        $commitPercent = if ($commitLimitMb -gt 0) { 100 * $commitMb / $commitLimitMb } else { 0 }
        $memorySnapshot = [pscustomobject]@{
            PhysicalUsedMb = [Math]::Round($physicalUsedMb, 1)
            PhysicalTotalMb = [Math]::Round($physicalTotalMb, 1)
            PhysicalPercent = [Math]::Round($physicalPercent, 1)
            CommitUsedMb = [Math]::Round($commitMb, 1)
            CommitLimitMb = [Math]::Round($commitLimitMb, 1)
            CommitPercent = [Math]::Round($commitPercent, 1)
            PagesPerSecond = [Math]::Round($pagesPerSecond, 1)
        }
    } catch {
        $errors += "Memory counters unavailable: $($_.Exception.Message)"
    }

    $processSnapshot = @()
    try {
        $coreCount = [Math]::Max(1, [Environment]::ProcessorCount)
        $processSamples = @((Get-Counter '\Process(*)\% Processor Time','\Process(*)\Working Set - Private','\Process(*)\ID Process').CounterSamples)
        $processes = @($processSamples |
            Where-Object { $_.Path -like '*\% processor time' -and $_.InstanceName -notin @('_total', 'idle') } |
            Sort-Object CookedValue -Descending |
            Select-Object -First 6)
        foreach ($process in $processes) {
            $cpuPercent = [Math]::Min(100, [double]$process.CookedValue / $coreCount)
            $memorySample = $processSamples |
                Where-Object { $_.InstanceName -eq $process.InstanceName -and $_.Path -like '*\working set - private' } |
                Select-Object -First 1
            $idSample = $processSamples |
                Where-Object { $_.InstanceName -eq $process.InstanceName -and $_.Path -like '*\id process' } |
                Select-Object -First 1
            $memoryMb = if ($memorySample) { [double]$memorySample.CookedValue / 1MB } else { 0 }
            $processId = if ($idSample) { [int]$idSample.CookedValue } else { 0 }
            $processUptimeSeconds = $null
            if ($processId -gt 0) {
                try { $processUptimeSeconds = [Math]::Max(0, ((Get-Date) - (Get-Process -Id $processId -ErrorAction Stop).StartTime).TotalSeconds) } catch {}
            }
            $processSnapshot += [pscustomobject]@{
                Name = [string]$process.InstanceName
                ProcessId = $processId
                CpuPercent = [Math]::Round($cpuPercent, 1)
                PrivateWorkingSetMb = [Math]::Round($memoryMb, 1)
                UptimeSeconds = $processUptimeSeconds
            }
        }
    } catch {
        $errors += "Process counters unavailable: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Host = [Environment]::MachineName
        SystemUptimeSeconds = $systemUptimeSeconds
        DashboardUptimeSeconds = [Math]::Max(0, ([DateTimeOffset]::Now - $DashboardStartedAt).TotalSeconds)
        Power = Get-PowerSnapshot
        Cpu = [pscustomobject]@{ TotalPercent = $cpuTotal; Cores = @($cpuCores) }
        Memory = $memorySnapshot
        Processes = @($processSnapshot)
        Errors = @($errors)
    }
}

function Get-SystemPanel {
    param($Snapshot, [int] $Width)
    $lines = @('SYSTEM', "$($Snapshot.Host) | host up $(Format-DurationSeconds $Snapshot.SystemUptimeSeconds)", "dashboard up $(Format-DurationSeconds $Snapshot.DashboardUptimeSeconds) | $([DateTimeOffset]::Parse($Snapshot.Timestamp).ToString('HH:mm:ss'))")
    $power = $Snapshot.Power
    if ($power) {
        $remaining = Format-DurationSeconds $power.BatteryLifeRemainingSeconds
        $powerLine = if ($power.PowerLineStatus -eq 'Offline') { "battery $($power.BatteryPercent)% | est $remaining left" } else { [string]$power.PowerLineStatus }
        $lines += "power $($power.State) | throttle $($power.ThrottlednessPercent)%"
        $lines += "$powerLine | limit $($power.PerformanceLimitPercent)% | freq $($power.MaximumFrequencyPercent)%"
        if ($power.ActivePlan) { $lines += "plan $($power.ActivePlan) | $($power.Scope)/$($power.Confidence)" }
    }
    $barWidth = [Math]::Max(5, $Width - 15)
    if ($null -ne $Snapshot.Cpu.TotalPercent) {
        $lines += ('CPU all [{0}] {1,3}%' -f (New-Bar $Snapshot.Cpu.TotalPercent $barWidth), [int]$Snapshot.Cpu.TotalPercent)
    }
    foreach ($cpu in @($Snapshot.Cpu.Cores)) {
        $lines += ('CPU {0,3} [{1}] {2,3}%' -f $cpu.Core, (New-Bar $cpu.Percent $barWidth), [int]$cpu.Percent)
    }
    $lines += ''
    if ($Snapshot.Memory) {
        $memory = $Snapshot.Memory
        $lines += ('RAM     [{0}] {1,3}%' -f (New-Bar $memory.PhysicalPercent $barWidth), [int]$memory.PhysicalPercent)
        $lines += ('        {0:N1}/{1:N1} GB' -f ($memory.PhysicalUsedMb / 1024), ($memory.PhysicalTotalMb / 1024))
        $lines += ('Commit  [{0}] {1,3}%' -f (New-Bar $memory.CommitPercent $barWidth), [int]$memory.CommitPercent)
        $lines += ('        {0:N1}/{1:N1} GB' -f ($memory.CommitUsedMb / 1024), ($memory.CommitLimitMb / 1024))
        $lines += ('Paging  {0:N1} pages/sec' -f $memory.PagesPerSecond)
    }
    $lines += ''
    $lines += 'BUSIEST PROCESSES'
    foreach ($process in @($Snapshot.Processes)) {
        $nameWidth = [Math]::Max(8, $Width - 34)
        $name = Limit-Text ([string]$process.Name) $nameWidth
        $uptime = Format-DurationSeconds $process.UptimeSeconds
        $lines += ('{0,-' + $nameWidth + '} {1,5:N1}% {2,7:N0} MB up {3}') -f $name, $process.CpuPercent, $process.PrivateWorkingSetMb, $uptime
    }
    $lines += @($Snapshot.Errors)
    return @($lines)
}

function Get-RawSnapshot {
    param($PullRequests, [hashtable] $Releases, $Commentary, $Workers, $System, [AllowNull()][string] $GitHubError, [AllowNull()][string] $Transcript)
    $prSnapshots = @()
    foreach ($record in @($PullRequests)) {
        $pr = $record.PullRequest
        $releaseKey = "$($record.Repository)#$($pr.number)"
        $release = if ($Releases.ContainsKey($releaseKey)) { $Releases[$releaseKey] } else { $null }
        $releaseSnapshot = $null
        if ($release) {
            $releaseSnapshot = [pscustomobject]@{
                Tag = $release.Tag
                Url = $release.Url
                Assets = @($release.Assets | ForEach-Object {
                    [pscustomobject]@{ Name = $_.name; SizeBytes = $_.size; DownloadUrl = $_.browser_download_url }
                })
            }
        }
        $prOpenSeconds = try { [Math]::Max(0, ([DateTimeOffset]::Now - [DateTimeOffset]$pr.createdAt).TotalSeconds) } catch { $null }
        $prSnapshots += [pscustomobject]@{
            Repository = $record.Repository
            Number = $pr.number
            Title = $pr.title
            Url = $pr.url
            Author = $pr.author.login
            Head = $pr.headRefName
            Base = $pr.baseRefName
            IsDraft = $pr.isDraft
            MergeState = $pr.mergeStateStatus
            WorkerState = Get-CheckState @($pr.statusCheckRollup)
            CreatedAt = $pr.createdAt
            UpdatedAt = $pr.updatedAt
            OpenSeconds = $prOpenSeconds
            Checks = @($pr.statusCheckRollup)
            TesterRelease = $releaseSnapshot
        }
    }
    return [pscustomobject]@{
        SchemaVersion = 2
        GeneratedAt = [DateTimeOffset]::Now.ToString('o')
        Repositories = @($Repository)
        GitHubError = $GitHubError
        PullRequests = @($prSnapshots)
        CodexWorkers = @($Workers)
        Transcript = [pscustomobject]@{ Path = $Transcript; Messages = @($Commentary) }
        System = $System
    }
}

function Get-PrPanel {
    param($PullRequests, [hashtable] $Releases, $Commentary, $Workers, [int] $Width, [string] $Transcript)
    $lines = @('CI PIPELINE', "Updated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  refresh ${IntervalSeconds}s")
    $records = @($PullRequests)
    if ($records.Count -eq 0) { $lines += 'No open pull requests.' }

    foreach ($repoGroup in @($records | Group-Object Repository)) {
        $lines += ''
        $lines += "+ $($repoGroup.Name)"
        foreach ($baseGroup in @($repoGroup.Group | Group-Object { $_.PullRequest.baseRefName })) {
            $lines += "  + target $($baseGroup.Name)"
            $prs = @($baseGroup.Group | Sort-Object { $_.PullRequest.number } -Descending)
            for ($prIndex = 0; $prIndex -lt $prs.Count; $prIndex++) {
                $record = $prs[$prIndex]
                $pr = $record.PullRequest
                $prLast = $prIndex -eq ($prs.Count - 1)
                $prJoint = if ($prLast) { '  `-' } else { '  |-' }
                $child = if ($prLast) { '     ' } else { '  |  ' }
                $state = if ($pr.isDraft) { 'DRAFT' } else { Get-CheckState @($pr.statusCheckRollup) }
                $lines += "$prJoint PR #$($pr.number) [$state] $($pr.title)"
                $age = Format-Age -Timestamp ($pr.updatedAt)
                $openSeconds = try { [Math]::Max(0, ([DateTimeOffset]::Now - [DateTimeOffset]$pr.createdAt).TotalSeconds) } catch { $null }
                $lines += "$child|- $($pr.headRefName) -> $($pr.baseRefName) | open $(Format-DurationSeconds $openSeconds) | updated $age"
                $lines += "$child|- merge $($pr.mergeStateStatus)"
                foreach ($check in @($pr.statusCheckRollup)) {
                    $lines += "$child|- $(Get-CheckLabel $check)"
                }
                if (@($pr.statusCheckRollup).Count -eq 0) { $lines += "$child|- [WAIT] no checks reported" }

                $releaseKey = "$($record.Repository)#$($pr.number)"
                if ($Releases.ContainsKey($releaseKey)) {
                    $release = $Releases[$releaseKey]
                    $assets = @($release.Assets)
                    $lines += "$child|- APK release $($release.Tag) ($($assets.Count) individual files)"
                    for ($assetIndex = 0; $assetIndex -lt $assets.Count; $assetIndex++) {
                        $asset = $assets[$assetIndex]
                        $sizeMb = [double]$asset.size / 1MB
                        $lines += "$child|  |- $($asset.name) ($('{0:N1}' -f $sizeMb) MB)"
                    }
                    $lines += "$child|  `- $($release.Url)"
                } else {
                    $lines += "$child|- APK release not published yet"
                }
                $lines += "$child`- $($pr.url)"
            }
        }
    }

    if (@($Workers).Count -gt 0) {
        $lines += ''
        $lines += 'CODEX WORKERS'
        foreach ($worker in @($Workers)) {
            $references = @()
            $references += @($worker.PullRequests | ForEach-Object { "PR #$_" })
            $references += @($worker.Issues | ForEach-Object { "issue #$_" })
            $referenceLabel = if ($references.Count -gt 0) { ' | ' + ($references -join ', ') } else { '' }
            $stateLabel = if ($worker.Outcome) { "$($worker.Activity)/$($worker.Outcome)" } else { [string]$worker.Activity }
            $runtimeLabel = if ($worker.Activity -eq 'COMPLETE') { "ran $(Format-DurationSeconds $worker.RuntimeSeconds)" } else { "running $(Format-DurationSeconds $worker.RuntimeSeconds)" }
            $providerLabel = if ($worker.Provider) { " | $($worker.Provider)@$($worker.Host)" } else { " | $($worker.Host)" }
            $lines += "+ [$stateLabel] $($worker.Name) ($($worker.Role))$referenceLabel$providerLabel"
            $lines += "  |- $runtimeLabel | last activity $(Format-Age -Timestamp $worker.LastActivityAt)"
            $lines += "  |- model $($worker.Model) / effort $($worker.ReasoningEffort) | approval $($worker.ModelApprovalState)"
            if ($worker.Summary) { $lines += "  `- $($worker.Summary)" }
        }
    }

    if (@($Commentary).Count -gt 0) {
        $lines += ''
        $lines += 'CODEX TASK TAIL'
        if ($Transcript) { $lines += "source: $Transcript" }
        foreach ($message in @($Commentary)) {
            $time = try { ([DateTimeOffset]::Parse($message.Timestamp).ToLocalTime()).ToString('HH:mm:ss') } catch { '--:--:--' }
            $lines += "$time  $($message.Text)"
        }
    }
    return @($lines | ForEach-Object { Limit-Text ([string]$_) $Width })
}

function Write-Dashboard {
    param([string[]] $Left, [string[]] $Right, [int] $Width, [bool] $Interactive, [ref] $PreviousHeight)
    $gap = 2
    $rightWidth = [Math]::Max(28, [int][Math]::Floor($Width / 3))
    $leftWidth = $Width - $rightWidth - $gap
    if ($Width -lt 100) {
        $combined = @($Left) + @('') + @($Right)
    } else {
        $height = [Math]::Max($Left.Count, $Right.Count)
        $combined = for ($i = 0; $i -lt $height; $i++) {
            $leftLine = if ($i -lt $Left.Count) { $Left[$i] } else { '' }
            $rightLine = if ($i -lt $Right.Count) { $Right[$i] } else { '' }
            (Pad-Line $leftLine $leftWidth) + (' ' * $gap) + (Limit-Text $rightLine $rightWidth)
        }
    }
    if ($Interactive) {
        try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Host }
        $heightToWrite = [Math]::Max($combined.Count, $PreviousHeight.Value)
        for ($i = 0; $i -lt $heightToWrite; $i++) {
            $line = if ($i -lt $combined.Count) { $combined[$i] } else { '' }
            [Console]::WriteLine((Pad-Line $line ($Width - 1)))
        }
        $PreviousHeight.Value = $combined.Count
    } else {
        $combined | Write-Output
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is required and was not found in PATH.'
}

if ([string]::IsNullOrWhiteSpace($TranscriptPath)) { $TranscriptPath = Find-LatestTranscript }
$dashboardStartedAt = [DateTimeOffset]::Now
$releaseCache = @{}
$releaseCacheAt = [DateTimeOffset]::MinValue
$lastPullRequests = @()
$githubError = $null
$previousHeight = 0
$interactive = -not $Once -and $OutputFormat -eq 'Console'
try { if ([Console]::IsOutputRedirected) { $interactive = $false } } catch { $interactive = $false }
if ($interactive) { Clear-Host }

do {
    try {
        $lastPullRequests = Get-OpenPullRequests $Repository
        $githubError = $null
    } catch {
        $githubError = $_.Exception.Message
    }
    if (([DateTimeOffset]::Now - $releaseCacheAt).TotalSeconds -ge $ReleaseRefreshSeconds) {
        try {
            $releaseCache = Get-TesterReleases $Repository
            $releaseCacheAt = [DateTimeOffset]::Now
        } catch {
            if (-not $githubError) { $githubError = "Release lookup failed: $($_.Exception.Message)" }
        }
    }

    $width = Get-TerminalWidth
    $rightWidth = [Math]::Max(28, [int][Math]::Floor($width / 3))
    $leftWidth = if ($width -lt 100) { $width } else { $width - $rightWidth - 2 }
    $commentary = @(Get-TranscriptCommentary $TranscriptPath $TranscriptLines)
    $workers = @(Get-CodexWorkers $TranscriptPath $WorkerLookbackMinutes $MaxWorkers)
    $system = Get-SystemSnapshot -DashboardStartedAt $dashboardStartedAt
    if ($OutputFormat -eq 'Json') {
        $snapshot = Get-RawSnapshot -PullRequests $lastPullRequests -Releases $releaseCache -Commentary $commentary -Workers $workers -System $system -GitHubError $githubError -Transcript $TranscriptPath
        Write-Output ($snapshot | ConvertTo-Json -Depth 12 -Compress)
    } else {
        $left = @(Get-PrPanel -PullRequests $lastPullRequests -Releases $releaseCache -Commentary $commentary -Workers $workers -Width $leftWidth -Transcript $TranscriptPath)
        if ($githubError) { $left = @("GITHUB ERROR: $githubError", '') + $left }
        $right = @(Get-SystemPanel -Snapshot $system -Width $rightWidth)
        Write-Dashboard $left $right $width $interactive ([ref]$previousHeight)
    }

    if (-not $Once) { Start-Sleep -Seconds $IntervalSeconds }
} while (-not $Once)
