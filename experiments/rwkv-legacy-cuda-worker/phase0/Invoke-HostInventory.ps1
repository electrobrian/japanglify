<#
.SYNOPSIS
    Read-only Phase 0 inventory for the RWKV legacy CUDA worker target.
.DESCRIPTION
    Collects Windows host, PowerShell, CPU, memory, display adapter, NVIDIA,
    CUDA, installed-program, TPM, and system-drive information without requiring
    administrator privileges or internet access.
.REQUIREMENTS
    Implements the inventory described by rwkv-legacy-cuda-worker/REQUIREMENTS.md
    section 4.1. Run with Windows PowerShell 5.1 on the physical target.
.OPERATOR INSTRUCTIONS
    Open a normal (non-elevated) PowerShell 5.1 prompt, change to this phase0
    directory, and run: .\Invoke-HostInventory.ps1
    The report and JSON summary are written beside this script.
.NOTES
    This script does not install, download, configure, mutate, benchmark, load,
    allocate, or execute a model. It does not change drivers, CUDA, services,
    power settings, firewall rules, registry values, or network configuration.
#>

$ErrorActionPreference = 'SilentlyContinue'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$reportPath = Join-Path $scriptDirectory 'host-inventory-report.txt'
$jsonPath = Join-Path $scriptDirectory 'host-inventory.json'

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $null
}

function Convert-ToReportLines {
    param(
        [object]$Value,
        [string]$Prefix = ''
    )
    $lines = @()
    if ($null -eq $Value) {
        return @($Prefix + '<unavailable>')
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $lines += Convert-ToReportLines -Value $Value[$key] -Prefix ($Prefix + $key + ': ')
        }
        return $lines
    }
    if (($Value -is [System.Array]) -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])) {
        foreach ($item in $Value) {
            $lines += Convert-ToReportLines -Value $item -Prefix ($Prefix + '- ')
        }
        return $lines
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $lines += Convert-ToReportLines -Value $property.Value -Prefix ($Prefix + $property.Name + ': ')
        }
        return $lines
    }
    return @($Prefix + [string]$Value)
}

function Get-CommandCapture {
    param(
        [string]$Name,
        [string[]]$Arguments
    )
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return [pscustomobject]@{ found = $false; path = $null; output = @() }
    }
    $output = @(& $command.Source @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{ found = $true; path = $command.Source; output = $output }
}

function Get-NvidiaRegistryEntries {
    $root = 'HKLM:\SOFTWARE\NVIDIA Corporation'
    $entries = @()
    if (-not (Test-Path $root)) {
        return $entries
    }
    $keys = @(Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue)
    $keys = @($root) + $keys
    foreach ($key in $keys) {
        $keyPath = if ($key -is [string]) { $key } else { $key.PSPath }
        $properties = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
        if ($null -ne $properties) {
            $values = [ordered]@{ path = $keyPath }
            foreach ($property in $properties.PSObject.Properties) {
                if ($property.Name -notlike 'PS*') {
                    $values[$property.Name] = $property.Value
                }
            }
            $entries += [pscustomobject]$values
        }
    }
    return $entries
}

function Get-InstalledMatchingPrograms {
    $locations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $programs = @()
    foreach ($location in $locations) {
        foreach ($item in @(Get-ItemProperty $location -ErrorAction SilentlyContinue)) {
            $name = [string](Get-PropertyValue -Object $item -Name 'DisplayName')
            if ($name -and $name -match '(?i)CUDA|NVIDIA|Visual C\+\+') {
                $programs += [pscustomobject]@{
                    name = $name
                    version = Get-PropertyValue -Object $item -Name 'DisplayVersion'
                    publisher = Get-PropertyValue -Object $item -Name 'Publisher'
                    installLocation = Get-PropertyValue -Object $item -Name 'InstallLocation'
                    registryPath = $item.PSPath
                }
            }
        }
    }
    return @($programs | Sort-Object name, version, registryPath -Unique)
}

$os = Get-WmiObject Win32_OperatingSystem
$powerShell = [ordered]@{
    version = [string]$PSVersionTable.PSVersion
    edition = $PSVersionTable.PSEdition
    clrVersion = [string]$PSVersionTable.CLRVersion
    buildVersion = $PSVersionTable.BuildVersion
    platform = $PSVersionTable.Platform
}
$processors = @(Get-WmiObject Win32_Processor | ForEach-Object {
    [pscustomobject]@{
        name = $_.Name
        cores = $_.NumberOfCores
        logicalProcessors = $_.NumberOfLogicalProcessors
        maxClockMHz = $_.MaxClockSpeed
    }
})
$memoryModules = @(Get-WmiObject Win32_PhysicalMemory | ForEach-Object {
    [pscustomobject]@{
        capacityBytes = $_.Capacity
        speedMHz = $_.Speed
        manufacturer = $_.Manufacturer
        partNumber = $_.PartNumber
    }
})
$videoAdapters = @(Get-WmiObject Win32_VideoController | ForEach-Object {
    [pscustomobject]@{
        name = $_.Name
        pciDeviceId = $_.PNPDeviceID
        adapterRamBytes = $_.AdapterRAM
        driverVersion = $_.DriverVersion
        driverDate = $_.DriverDate
        status = $_.Status
    }
})
$tpm = $null
try {
    $tpm = Get-Tpm -ErrorAction Stop | Select-Object TpmPresent, TpmReady, TpmEnabled, ManufacturerIdTxt, ManufacturerVersion, ManagedAuthLevel
} catch {
    $tpm = [pscustomobject]@{ unavailable = $true; reason = 'Get-Tpm unavailable or access was denied' }
}
$systemDrive = [string]$env:SystemDrive
$disk = Get-WmiObject Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $systemDrive) | Select-Object DeviceID, Size, FreeSpace, VolumeName
$nvcc = Get-CommandCapture -Name 'nvcc.exe' -Arguments @('--version')
$nvidiaSmi = Get-CommandCapture -Name 'nvidia-smi.exe' -Arguments @()

$summary = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    host = [ordered]@{
        computerName = $env:COMPUTERNAME
        userName = $env:USERNAME
        systemDrive = $systemDrive
    }
    operatingSystem = [ordered]@{
        caption = Get-PropertyValue -Object $os -Name 'Caption'
        version = Get-PropertyValue -Object $os -Name 'Version'
        architecture = Get-PropertyValue -Object $os -Name 'OSArchitecture'
        servicePack = Get-PropertyValue -Object $os -Name 'ServicePackMajorVersion'
        buildNumber = Get-PropertyValue -Object $os -Name 'BuildNumber'
    }
    powerShell = $powerShell
    processors = $processors
    physicalMemory = $memoryModules
    videoAdapters = $videoAdapters
    nvidiaRegistry = @(Get-NvidiaRegistryEntries)
    cudaToolkit = $nvcc
    nvidiaSmi = $nvidiaSmi
    installedMatchingPrograms = @(Get-InstalledMatchingPrograms)
    tpm = $tpm
    systemDrive = $disk
    actionsTaken = @('read-only WMI and registry inspection', 'read-only PATH command discovery')
    actionsNotTaken = @('model execution', 'driver or toolkit installation', 'network access', 'device allocation probe', 'system configuration changes')
}

$json = $summary | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$report = @()
$report += 'RWKV Legacy CUDA Worker - Phase 0 Host Inventory'
$report += 'Generated UTC: ' + $summary.generatedAtUtc
$report += 'Computer: ' + [string]$summary.host.computerName
$report += ''
$report += 'Operating system:'
$report += Convert-ToReportLines -Value $summary.operatingSystem -Prefix '  '
$report += 'PowerShell:'
$report += Convert-ToReportLines -Value $summary.powerShell -Prefix '  '
$report += 'CPU:'
$report += Convert-ToReportLines -Value $summary.processors -Prefix '  '
$report += 'Physical RAM modules:'
$report += Convert-ToReportLines -Value $summary.physicalMemory -Prefix '  '
$report += 'Display/video adapters:'
$report += Convert-ToReportLines -Value $summary.videoAdapters -Prefix '  '
$report += 'CUDA-related entries under HKLM:\SOFTWARE\NVIDIA Corporation:'
$report += Convert-ToReportLines -Value $summary.nvidiaRegistry -Prefix '  '
$report += 'nvcc.exe:'
$report += Convert-ToReportLines -Value $summary.cudaToolkit -Prefix '  '
$report += 'nvidia-smi.exe:'
$report += Convert-ToReportLines -Value $summary.nvidiaSmi -Prefix '  '
$report += 'Installed programs matching CUDA, NVIDIA, or Visual C++:'
$report += Convert-ToReportLines -Value $summary.installedMatchingPrograms -Prefix '  '
$report += 'TPM:'
$report += Convert-ToReportLines -Value $summary.tpm -Prefix '  '
$report += 'System drive free space:'
$report += Convert-ToReportLines -Value $summary.systemDrive -Prefix '  '
$report += ''
$report += 'Phase 0 inventory complete. No model, driver, or network action was taken.'
[System.IO.File]::WriteAllText($reportPath, ($report -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))

Write-Output 'Phase 0 inventory complete. No model, driver, or network action was taken.'
Write-Output ('Report: ' + $reportPath)
Write-Output ('JSON: ' + $jsonPath)
