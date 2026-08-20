# Verifies the opt-in image preparation fast path stays disabled for a fresh install.
#
# This intentionally inspects the default supplied to SharedPreferences rather
# than a Preference UI value: the runtime default must remain false even if the
# settings XML is unavailable or a preference has never been rendered.

param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$sourcePath = Join-Path $RepositoryRoot "app/src/main/java/com/japanglify/app/clipboard/ClipboardImageRenderCache.kt"
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Expected source file was not found: $sourcePath"
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$expected = 'getBoolean(PreferencesRepository.KEY_PREEMPTIVE_IMAGE_RENDER, false)'

if (-not $source.Contains($expected)) {
    throw "Preemptive image preparation is no longer disabled by default. Expected $expected in $sourcePath"
}

Write-Host "PASS: preemptive image preparation defaults to off for a fresh preference store."
