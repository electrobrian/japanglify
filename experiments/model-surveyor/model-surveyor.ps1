[CmdletBinding()]
param(
    [ValidateSet('inventory', 'recommend')]
    [string] $Command = 'inventory',
    [string] $OutputJson,
    [string] $HostReport,
    [string] $CatalogPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:CollectionWarnings = @()

if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $PSScriptRoot 'catalog\candidates.json'
}

function Get-SurveyWmi {
    param([Parameter(Mandatory = $true)][string] $ClassName)
    try {
        return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop)
    } catch {
        try {
            return @(Get-WmiObject -Class $ClassName -ErrorAction Stop)
        } catch {
            $script:CollectionWarnings += "Unable to read $ClassName through CIM or WMI: $($_.Exception.Message)"
            return @()
        }
    }
}

function ConvertTo-Bytes {
    param($Value, [int64] $Multiplier = 1)
    if ($null -eq $Value) { return $null }
    try { return [int64]$Value * $Multiplier } catch { return $null }
}

function Get-SafeProperty {
    param($Object, [Parameter(Mandatory = $true)][string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-CommandVersion {
    param([string] $Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) { return $null }
    return [pscustomobject]@{ path = $command.Source; version = $command.Version.ToString() }
}

function Get-DeviceProfile {
    param($VideoController)

    $name = [string]$VideoController.Name
    $pnpId = [string]$VideoController.PNPDeviceID
    $profile = [ordered]@{
        vendor = 'unknown'
        acceleratorClass = 'unknown'
        computeCapability = $null
        sharedMemoryLikely = $false
        legacyWarning = $null
    }

    if ($pnpId -match 'VEN_10DE' -or $name -match 'NVIDIA|GeForce|Quadro') {
        $profile.vendor = 'nvidia'
        $profile.acceleratorClass = 'cuda-candidate'
        if ($name -match '8600\s*GT') {
            $profile.computeCapability = '1.1'
            $profile.legacyWarning = 'GeForce 8600 GT is a legacy sm_11 target; current CUDA/ML runtimes are not assumed compatible.'
        }
    } elseif ($pnpId -match 'VEN_1002' -or $name -match 'AMD|ATI|Radeon') {
        $profile.vendor = 'amd'
        $profile.acceleratorClass = 'opencl-or-cal-candidate'
        if ($name -match 'HD\s*4200|Radeon\s*4200') {
            $profile.sharedMemoryLikely = $true
            $profile.legacyWarning = 'Radeon HD 4200 is an AMD 785G integrated GPU; it is expected to use shared system memory and requires a legacy compute runtime investigation.'
        }
    } elseif ($pnpId -match 'VEN_8086' -or $name -match 'Intel') {
        $profile.vendor = 'intel'
        $profile.acceleratorClass = 'integrated-gpu-candidate'
        $profile.sharedMemoryLikely = $true
    }

    return [pscustomobject]$profile
}

function Get-OtherResourceProfile {
    param($Device)

    $name = [string]$Device.Name
    $pnpClass = [string]$Device.PNPClass
    $pnpId = [string]$Device.PNPDeviceID
    $manufacturer = [string]$Device.Manufacturer
    $text = ($name + ' ' + $pnpClass + ' ' + $manufacturer + ' ' + $pnpId)

    $profile = [ordered]@{
        category = $null
        classification = $null
        likelyUse = $null
        caution = $null
    }

    if ($pnpId -match 'VEN_10EE|VEN_1172' -or $text -match 'Xilinx|Altera|Intel\(R\).*FPGA|Lattice.*FPGA|Microsemi.*FPGA') {
        $profile.category = 'fpga-or-programmable-logic'
        $profile.classification = 'programmable-but-research-only'
        $profile.likelyUse = 'Potential custom dataflow, DSP, or accelerator workloads after exact-board and toolchain identification.'
        $profile.caution = 'PCI identity alone does not establish accessible fabric, available tools, bitstream ownership, or safe reprogramming path.'
    } elseif ($pnpClass -eq 'Net' -and $pnpId -match '^PCI\\') {
        $profile.category = 'network-controller'
        $profile.classification = 'sensor-offload'
        $profile.likelyUse = 'Packet capture, flow counters, timestamps, checksum/DMA offload, and host-side network-security analysis.'
        $profile.caution = 'Typical consumer/enterprise NIC firmware is not a practical or safe general numeric-compute target; do not flash it for this experiment.'
    } elseif (($pnpClass -eq 'MEDIA' -and $pnpId -match '^(PCI|HDAUDIO)\\') -or ($pnpClass -eq 'System' -and $pnpId -match '^PCI\\' -and $text -match 'High Definition Audio')) {
        $profile.category = 'audio-controller-or-codec'
        $profile.classification = 'sensor-offload'
        $profile.likelyUse = 'Audio acquisition for host/GPU FFT, spectral anomaly, vibration, and acoustic-event analysis.'
        $profile.caution = 'Most onboard audio codecs are fixed-function; they are not a general programmable DSP.'
    } elseif ($text -match 'Trusted Platform Module|\bTPM\b|Security Device') {
        $profile.category = 'security-processor'
        $profile.classification = 'firmware-bound-not-a-compute-target'
        $profile.likelyUse = 'Key storage, measured boot, attestation, and worker identity protection.'
        $profile.caution = 'Do not treat a TPM as a general accelerator or attempt firmware changes.'
    } elseif ($text -match 'Management Engine|Baseboard Management|BMC|DASH|ASF') {
        $profile.category = 'management-controller'
        $profile.classification = 'firmware-bound-not-a-compute-target'
        $profile.likelyUse = 'Out-of-band inventory, health signals, wake/power management, and remote-console investigation when documented.'
        $profile.caution = 'Management firmware is security-sensitive and not a general compute target.'
    } elseif ($pnpClass -match 'SCSIAdapter|HDC|IDE' -or $text -match 'SATA|RAID|Storage Controller') {
        $profile.category = 'storage-controller'
        $profile.classification = 'firmware-bound-not-a-compute-target'
        $profile.likelyUse = 'DMA, storage telemetry, and integrity/throughput measurement.'
        $profile.caution = 'Controller firmware is not suitable for arbitrary compute; preserve data integrity.'
    }

    if ($null -eq $profile.category) { return $null }
    return [pscustomobject]$profile
}

function Get-OtherProgrammableResources {
    $devices = Get-SurveyWmi 'Win32_PnPEntity'
    $resources = @()
    foreach ($device in $devices) {
        $profile = Get-OtherResourceProfile $device
        if ($null -eq $profile) { continue }
        $resources += [pscustomobject]@{
            name = [string]$device.Name
            manufacturer = [string]$device.Manufacturer
            pnpClass = [string]$device.PNPClass
            pnpDeviceId = [string]$device.PNPDeviceID
            status = [string]$device.Status
            profile = $profile
        }
    }
    return $resources
}

function Get-HostInventory {
    $os = Get-SurveyWmi 'Win32_OperatingSystem' | Select-Object -First 1
    $computer = Get-SurveyWmi 'Win32_ComputerSystem' | Select-Object -First 1
    $product = Get-SurveyWmi 'Win32_ComputerSystemProduct' | Select-Object -First 1
    $baseBoard = Get-SurveyWmi 'Win32_BaseBoard' | Select-Object -First 1
    $processors = Get-SurveyWmi 'Win32_Processor'
    $videoControllers = Get-SurveyWmi 'Win32_VideoController'
    $batteries = Get-SurveyWmi 'Win32_Battery'
    $otherResources = @(Get-OtherProgrammableResources)

    $cpuRows = @($processors | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Name
            manufacturer = [string]$_.Manufacturer
            cores = [int]$_.NumberOfCores
            logicalProcessors = [int]$_.NumberOfLogicalProcessors
            maxClockMHz = [int]$_.MaxClockSpeed
            currentClockMHz = [int]$_.CurrentClockSpeed
            architecture = [int]$_.Architecture
        }
    })

    $gpuRows = @($videoControllers | ForEach-Object {
        $profile = Get-DeviceProfile $_
        $wmiVram = ConvertTo-Bytes $_.AdapterRAM
        [pscustomobject]@{
            name = [string]$_.Name
            pnpDeviceId = [string]$_.PNPDeviceID
            driverVersion = [string]$_.DriverVersion
            driverDate = [string]$_.DriverDate
            videoProcessor = [string]$_.VideoProcessor
            status = [string]$_.Status
            adapterRamBytes = $wmiVram
            vramEvidence = @([pscustomobject]@{
                source = 'Win32_VideoController.AdapterRAM'
                bytes = $wmiVram
                confidence = if ($null -eq $wmiVram -or $wmiVram -le 0) { 'none' } else { 'low' }
                note = 'WMI adapter RAM can be absent, truncated, or reflect shared allocation rather than physical VRAM.'
            })
            profile = $profile
        }
    })

    $totalRam = ConvertTo-Bytes (Get-SafeProperty $computer 'TotalPhysicalMemory')
    $freeRam = ConvertTo-Bytes (Get-SafeProperty $os 'FreePhysicalMemory') 1KB
    $batteryRows = @($batteries | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Name
            status = [string]$_.Status
            estimatedChargeRemainingPercent = $_.EstimatedChargeRemaining
            estimatedRunTimeMinutes = $_.EstimatedRunTime
        }
    })

    $toolchains = @(
        [pscustomobject]@{ name = 'powershell'; detected = $true; detail = $PSVersionTable.PSVersion.ToString() },
        [pscustomobject]@{ name = 'nvcc'; detected = ($null -ne (Get-Command nvcc -ErrorAction SilentlyContinue)); detail = (Get-CommandVersion nvcc) },
        [pscustomobject]@{ name = 'nvidia-smi'; detected = ($null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)); detail = (Get-CommandVersion nvidia-smi) },
        [pscustomobject]@{ name = 'cl'; detected = ($null -ne (Get-Command cl -ErrorAction SilentlyContinue)); detail = (Get-CommandVersion cl) },
        [pscustomobject]@{ name = 'cmake'; detected = ($null -ne (Get-Command cmake -ErrorAction SilentlyContinue)); detail = (Get-CommandVersion cmake) },
        [pscustomobject]@{ name = 'git'; detected = ($null -ne (Get-Command git -ErrorAction SilentlyContinue)); detail = (Get-CommandVersion git) }
    )

    $cpuCores = 0
    foreach ($cpu in $cpuRows) {
        $cores = Get-SafeProperty $cpu 'cores'
        if ($null -ne $cores) { $cpuCores += [int]$cores }
    }
    $tasks = @()
    if ($totalRam -ge 8GB) {
        $tasks += [pscustomobject]@{ assignment = 'cpu'; task = 'model checking, static analysis, conversion, hashing, and compile work'; confidence = 'medium'; reason = 'At least 8 GiB physical memory detected.' }
    }
    if ($cpuCores -ge 2) {
        $tasks += [pscustomobject]@{ assignment = 'cpu'; task = 'parallel test and build jobs with bounded concurrency'; confidence = 'medium'; reason = 'At least two physical CPU cores detected.' }
    }
    foreach ($gpu in $gpuRows) {
        if ($gpu.profile.acceleratorClass -ne 'unknown') {
            $tasks += [pscustomobject]@{ assignment = 'gpu'; task = 'bounded numeric microbenchmarks and architecture-specific runtime investigation'; confidence = 'low'; reason = $gpu.profile.legacyWarning }
        }
    }

    $platformWarnings = @()
    $productName = [string](Get-SafeProperty $product 'Name')
    $hasAmdGpu = @($gpuRows | Where-Object { $_.profile.vendor -eq 'amd' }).Count -gt 0
    if ($productName -match 'Compaq 6005 Pro' -and -not $hasAmdGpu) {
        $platformWarnings += 'This HP Compaq 6005 Pro platform normally includes AMD 785G/Radeon HD 4200 integrated graphics, but no AMD display adapter is currently enumerated. Treat it as disabled/unavailable until BIOS and driver status are verified.'
    }

    return [pscustomobject]@{
        schemaVersion = 1
        toolVersion = '0.1.0-mvp'
        catalogVersion = '2026-08-20'
        capturedAt = [DateTime]::UtcNow.ToString('o')
        host = [pscustomobject]@{
            name = [Environment]::MachineName
            platform = [pscustomobject]@{
                manufacturer = [string](Get-SafeProperty $computer 'Manufacturer')
                model = [string](Get-SafeProperty $computer 'Model')
                product = $productName
                baseBoardManufacturer = [string](Get-SafeProperty $baseBoard 'Manufacturer')
                baseBoardProduct = [string](Get-SafeProperty $baseBoard 'Product')
            }
            os = [pscustomobject]@{
                caption = [string](Get-SafeProperty $os 'Caption')
                version = [string](Get-SafeProperty $os 'Version')
                buildNumber = [string](Get-SafeProperty $os 'BuildNumber')
                architecture = [string](Get-SafeProperty $os 'OSArchitecture')
            }
            totalPhysicalMemoryBytes = $totalRam
            freePhysicalMemoryBytes = $freeRam
        }
        cpus = $cpuRows
        gpus = $gpuRows
        otherProgrammableResources = @($otherResources)
        power = [pscustomobject]@{ batteries = $batteryRows; telemetryNote = 'Battery, temperature, clock, and throttle data may be unavailable without vendor APIs.' }
        toolchains = $toolchains
        hostTaskSuitability = $tasks
        warnings = @(
            'Inventory is read-only. No model compatibility claim is a substitute for a physical runtime benchmark.',
            'VRAM values from WMI are low-confidence until reconciled with a device-specific allocation probe or vendor utility.'
        ) + @($platformWarnings) + @($script:CollectionWarnings)
    }
}

function Get-BytesEstimate {
    param([double] $ParametersMillion, [double] $BitsPerWeight, [double] $OverheadFactor = 1.15)
    return [int64]($ParametersMillion * 1000000 * $BitsPerWeight / 8 * $OverheadFactor)
}

function Get-CandidateRecommendations {
    param($Inventory, [string] $CatalogFile)
    if (-not (Test-Path -LiteralPath $CatalogFile)) { throw "Catalog not found: $CatalogFile" }
    $catalog = Get-Content -Raw -LiteralPath $CatalogFile | ConvertFrom-Json
    $recommendations = @()

    foreach ($candidate in $catalog.candidates) {
        foreach ($gpu in $Inventory.gpus) {
            if ($candidate.preferredVendor -ne $gpu.profile.vendor) { continue }
            $weightBytes = Get-BytesEstimate $candidate.parametersMillion $candidate.quantizationBits
            $workingBytes = [int64]($weightBytes * $candidate.runtimeMultiplier)
            $available = $gpu.adapterRamBytes
            $fitsKnown = ($null -ne $available -and $available -gt $workingBytes)
            $classification = 'unknown'
            $confidence = 'low'
            $gaps = @()

            if ($gpu.profile.computeCapability -eq '1.1') {
                $classification = $candidate.legacyCudaClassification
                $gaps += 'A current prebuilt runtime for sm_11 has not been verified; custom legacy CUDA work is required before execution.'
                if (-not $fitsKnown) { $gaps += 'WMI VRAM cannot prove the planned working set fits; verify physical VRAM and a display-safe allocation budget.' }
            } elseif ($gpu.profile.sharedMemoryLikely) {
                $classification = 'adaptable-research'
                $gaps += 'Integrated GPU uses shared system memory; legacy AMD OpenCL/CAL support and concurrent CPU bandwidth effects require measurement.'
            } else {
                $classification = 'unknown'
                $gaps += 'No runtime/operator compatibility profile has been validated for this adapter.'
            }

            $recommendations += [pscustomobject]@{
                modelId = $candidate.id
                displayName = $candidate.name
                role = $candidate.role
                architecture = $candidate.architecture
                targetGpu = $gpu.name
                classification = $classification
                confidence = $confidence
                memory = [pscustomobject]@{
                    estimatedWeightBytes = $weightBytes
                    estimatedWorkingSetBytes = $workingBytes
                    wmiReportedAdapterRamBytes = $available
                    fitFromWmiEvidence = $fitsKnown
                }
                nextStep = $candidate.nextStep
                gaps = $gaps
                evidence = $candidate.evidence
            }
        }
    }
    return $recommendations
}

if ($Command -eq 'inventory') {
    $report = Get-HostInventory
} else {
    if ($HostReport) {
        $report = Get-Content -Raw -LiteralPath $HostReport | ConvertFrom-Json
    } else {
        $report = Get-HostInventory
    }
    $report | Add-Member -Force -NotePropertyName candidates -NotePropertyValue @(Get-CandidateRecommendations $report $CatalogPath)
}

$json = $report | ConvertTo-Json -Depth 12
if ($OutputJson) {
    $outputDirectory = Split-Path -Parent $OutputJson
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) { throw "Output directory does not exist: $outputDirectory" }
    $outputPath = [System.IO.Path]::GetFullPath($OutputJson)
    [System.IO.File]::WriteAllText($outputPath, $json + [Environment]::NewLine)
}

Write-Output $json

