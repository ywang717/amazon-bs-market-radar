$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers/LegacyRegistry.ps1')
Import-Module (Join-Path $projectRoot 'src/BestSellersCaptureReceipt.psm1') -Force

Describe 'Capture receipt timestamp preservation' {
    BeforeEach {
        $script:timestampRegistry = New-LegacyCategoryRegistryFixture -ProjectRoot $projectRoot -Root (Join-Path $TestDrive 'timestamp-registry')
    }

    It 'preserves the source timestamp instant and milliseconds in Pacific receipt metadata' -TestCases @(
        @{Name='utc'; ObservedAt='2026-08-13T00:00:03.307Z'},
        @{Name='pacific-offset'; ObservedAt='2026-08-12T17:00:03.307-07:00'}
    ) {
        param($Name,$ObservedAt)
        $snapshotPath = Join-Path $TestDrive ($Name + '-snapshot.json')
        $snapshot = Get-Content (Join-Path $projectRoot 'web/data/verified-snapshot-2026-08-12.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.observed_at = $ObservedAt
        [IO.File]::WriteAllText($snapshotPath,($snapshot | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
        $sourceHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $script:timestampRegistry.SourceConfigPath -RegistryPath $script:timestampRegistry.RegistryPath

        $receipt.observed_at | Should Be '2026-08-12T17:00:03.307-07:00'
        ([DateTimeOffset]$receipt.observed_at).UtcTicks | Should Be ([DateTimeOffset]$ObservedAt).UtcTicks
        $receipt.snapshot_sha256 | Should Be $sourceHash
        (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should Be $sourceHash
    }
}
