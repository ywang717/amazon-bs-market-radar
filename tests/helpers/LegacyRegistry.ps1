# Explicit historical three-category contract for pre-Garden fixtures.
# Production Registry and validation are never modified.
function New-LegacyCategoryRegistryFixture {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,[Parameter(Mandatory=$true)][string]$Root)
    $configRoot = Join-Path $Root 'config'
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    $raw = Get-Content (Join-Path $ProjectRoot 'config/category-registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $keys = @('pressure_washers','sump_pumps','pressure_washer_accessories')
    $raw.categories = @($raw.categories | Where-Object { $_.category_key -in $keys })
    foreach ($category in $raw.categories) {
        foreach ($property in @('classification_config_path','attribute_schema_path')) {
            $relative = [string]$category.$property
            $destination = Join-Path $Root $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item (Join-Path $ProjectRoot $relative) $destination -Force
        }
    }
    $registryPath = Join-Path $configRoot 'category-registry.json'
    [IO.File]::WriteAllText($registryPath,($raw|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
    $sources = Get-Content (Join-Path $ProjectRoot 'config/best-sellers-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $sources.sources = @($sources.sources | Where-Object { $_.category_key -in $keys })
    $sourcePath = Join-Path $configRoot 'best-sellers-sources.json'
    [IO.File]::WriteAllText($sourcePath,($sources|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
    [pscustomobject]@{RegistryPath=$registryPath;SourceConfigPath=$sourcePath;Root=$Root}
}
