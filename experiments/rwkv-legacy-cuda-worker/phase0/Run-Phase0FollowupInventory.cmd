@echo off
setlocal
set "SELF=%~f0"
set "OUT=%~dp0Invoke-Phase0FollowupInventory.ps1"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$self=$env:SELF; $out=$env:OUT; $begin='### BEGIN POWERSHELL '+'PAYLOAD ###'; $finish='### END POWERSHELL '+'PAYLOAD ###'; $lines=[System.IO.File]::ReadAllLines($self); $start=[Array]::IndexOf($lines,$begin); $end=[Array]::IndexOf($lines,$finish); if($start -lt 0 -or $end -le $start){throw 'Embedded PowerShell payload markers were not found.'}; $payload=$lines[($start+1)..($end-1)] -join [Environment]::NewLine; [System.IO.File]::WriteAllText($out,$payload,(New-Object System.Text.UTF8Encoding($false))); & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $out; exit $LASTEXITCODE"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo Phase 0 follow-up inventory failed with exit code %RC%.
) else (
    echo.
    echo Phase 0 follow-up inventory completed.
    echo The JSON and report files are beside this command file.
)
echo.
pause
exit /b %RC%

### BEGIN POWERSHELL PAYLOAD ###
<#$
.SYNOPSIS
    Read-only follow-up inventory for the RWKV legacy CUDA Phase 0 gate.
.NOTES
    This embedded script does not install, download, allocate, benchmark, or
    execute CUDA. It does not change drivers, services, registry values, power
    settings, firewall rules, or network configuration.
#>

$ErrorActionPreference = 'SilentlyContinue'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$reportPath = Join-Path $scriptDirectory 'phase0-followup-report.txt'
$jsonPath = Join-Path $scriptDirectory 'phase0-followup.json'

function Get-CommandInfo {
    param([string]$Name)
    $commands = @(Get-Command $Name -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) { return [pscustomobject]@{ found = $false; paths = @() } }
    return [pscustomobject]@{ found = $true; paths = @($commands | ForEach-Object { $_.Source }) }
}

function Get-RegistrySnapshot {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [pscustomobject]@{ path = $Path; present = $false; values = @{} } }
    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    $values = [ordered]@{}
    if ($null -ne $item) {
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -notlike 'PS*') { $values[$property.Name] = $property.Value }
        }
    }
    return [pscustomobject]@{ path = $Path; present = $true; values = [pscustomobject]$values }
}

function Get-PathEvidence {
    param([string[]]$Paths)
    return @($Paths | ForEach-Object {
        [pscustomobject]@{
            path = $_
            exists = Test-Path $_
            item = if (Test-Path $_) { (Get-Item $_ -ErrorAction SilentlyContinue).FullName } else { $null }
        }
    })
}

function Convert-ToReportLines {
    param([object]$Value, [string]$Prefix = '')
    if ($null -eq $Value) { return @($Prefix + '<unavailable>') }
    if ($Value -is [System.Collections.IDictionary]) {
        $lines = @()
        foreach ($key in $Value.Keys) { $lines += Convert-ToReportLines $Value[$key] ($Prefix + $key + ': ') }
        return $lines
    }
    if (($Value -is [System.Array]) -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])) {
        $lines = @()
        foreach ($item in $Value) { $lines += Convert-ToReportLines $item ($Prefix + '- ') }
        return $lines
    }
    if ($Value -is [pscustomobject]) {
        $lines = @()
        foreach ($property in $Value.PSObject.Properties) { $lines += Convert-ToReportLines $property.Value ($Prefix + $property.Name + ': ') }
        return $lines
    }
    return @($Prefix + [string]$Value)
}

$tpm = $null
try { $tpm = Get-Tpm -ErrorAction Stop | Select-Object * }
catch { $tpm = [pscustomobject]@{ unavailable = $true; reason = 'Get-Tpm unavailable or access was denied' } }

$summary = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    computerName = $env:COMPUTERNAME
    displayMonitors = @(Get-WmiObject Win32_DesktopMonitor | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name; pnpDeviceId = $_.PNPDeviceID; screenWidth = $_.ScreenWidth
            screenHeight = $_.ScreenHeight; pixelsPerXLogicalInch = $_.PixelsPerXLogicalInch
            pixelsPerYLogicalInch = $_.PixelsPerYLogicalInch; status = $_.Status
        }
    })
    nvidiaDisplayDriverRegistry = @(
        Get-RegistrySnapshot 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak'
        Get-RegistrySnapshot 'HKLM:\SOFTWARE\NVIDIA Corporation\Installer2'
        Get-RegistrySnapshot 'HKLM:\SYSTEM\CurrentControlSet\Control\Video'
    )
    tpm = $tpm
    pathTools = [ordered]@{
        nvcc = Get-CommandInfo 'nvcc.exe'
        nvidiaSmi = Get-CommandInfo 'nvidia-smi.exe'
        nvidiaBugReport = Get-CommandInfo 'nvidia-bug-report.exe'
    }
    commonCudaPaths = Get-PathEvidence @(
        'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
        'C:\Program Files (x86)\NVIDIA GPU Computing Toolkit\CUDA'
        'C:\Program Files\NVIDIA Corporation\NVSMI'
        'C:\ProgramData\NVIDIA Corporation\CUDA Samples'
        'C:\CUDA'
    )
    actionsNotTaken = @('model execution','driver or toolkit installation','network access','GPU memory allocation probe','benchmarking','system configuration changes')
}

$json = $summary | ConvertTo-Json -Depth 10
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, $json, $utf8)
$report = @('RWKV Legacy CUDA Worker - Phase 0 Follow-up Inventory',('Generated UTC: ' + $summary.generatedAtUtc),('Computer: ' + $summary.computerName),'')
$report += 'Display monitors:'; $report += Convert-ToReportLines $summary.displayMonitors '  '
$report += 'NVIDIA driver registry snapshots:'; $report += Convert-ToReportLines $summary.nvidiaDisplayDriverRegistry '  '
$report += 'TPM:'; $report += Convert-ToReportLines $summary.tpm '  '
$report += 'PATH tools:'; $report += Convert-ToReportLines $summary.pathTools '  '
$report += 'Common CUDA paths:'; $report += Convert-ToReportLines $summary.commonCudaPaths '  '
$report += ''; $report += 'Phase 0 follow-up inventory complete. No allocation, model, driver, or network action was taken.'
[System.IO.File]::WriteAllText($reportPath, ($report -join [Environment]::NewLine), $utf8)
Write-Output 'Phase 0 follow-up inventory complete. No allocation, model, driver, or network action was taken.'
Write-Output ('Report: ' + $reportPath)
Write-Output ('JSON: ' + $jsonPath)
### END POWERSHELL PAYLOAD ###
