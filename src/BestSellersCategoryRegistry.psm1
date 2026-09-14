Set-StrictMode -Version Latest

function Read-CategoryRegistryJson {
    param(
        [Parameter(Mandatory=$true)][string]$LiteralPath,
        [Parameter(Mandatory=$true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "$Description does not exist: $LiteralPath"
    }

    try {
        return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$Description is not valid JSON: $LiteralPath"
    }
}

function Resolve-CategoryRegistryProjectRoot {
    param([Parameter(Mandatory=$true)][string]$RegistryPath)

    $registryDirectory = Split-Path -Parent $RegistryPath
    if ([string]::Equals((Split-Path -Leaf $registryDirectory), 'config', [StringComparison]::OrdinalIgnoreCase)) {
        return [IO.Path]::GetFullPath((Split-Path -Parent $registryDirectory))
    }
    return [IO.Path]::GetFullPath($registryDirectory)
}

function Resolve-CategoryRegistryReference {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$Reference,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $normalizedReference = $Reference.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $resolved = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $normalizedReference))
    $rootPrefix = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes the project root: $Reference"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Description does not exist: $Reference"
    }
    return $resolved
}

function Read-CategoryRegistryAttributeSchema {
    param([Parameter(Mandatory=$true)][string]$Path)

    $schema = Read-CategoryRegistryJson -LiteralPath $Path -Description 'Category attribute schema'
    if ($null -eq $schema -or
        $null -eq $schema.PSObject.Properties['schema_version'] -or
        [string]$schema.schema_version -cne 'product-attribute-schema-v1') {
        throw "Category attribute schema has an unsupported schema version: $Path"
    }
    if ($null -eq $schema.PSObject.Properties['product_types'] -or $null -eq $schema.product_types) {
        throw "Category attribute schema requires product_types: $Path"
    }

    $actualTypes = @($schema.product_types.PSObject.Properties.Name)
    if ($actualTypes.Count -eq 0 -or 'unknown' -cnotin $actualTypes) {
        throw "Category attribute schema must define product types including unknown: $Path"
    }

    foreach ($property in @($schema.product_types.PSObject.Properties)) {
        if ($property.Name -cnotmatch '^[a-z][a-z0-9_]*$') {
            throw "Category attribute schema contains an invalid product type: $($property.Name)"
        }
        if (-not ($property.Value -is [System.Array])) {
            throw "Category attribute schema product type '$($property.Name)' must contain an attribute array."
        }
        $attributes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($attribute in @($property.Value)) {
            $attributeName = [string]$attribute
            if ([string]::IsNullOrWhiteSpace($attributeName) -or -not $attributes.Add($attributeName)) {
                throw "Category attribute schema product type '$($property.Name)' contains an empty or duplicate attribute."
            }
        }
    }
    return $schema
}

function Assert-CategoryRegistryClassificationConfig {
    param([Parameter(Mandatory=$true)][string]$Path)

    $config = Read-CategoryRegistryJson -LiteralPath $Path -Description 'Category classification config'
    if ($null -eq $config -or
        $null -eq $config.PSObject.Properties['schema_version'] -or
        $null -eq $config.PSObject.Properties['rule_version'] -or
        [string]$config.schema_version -cne 'product-classification-config-v1' -or
        [string]::IsNullOrWhiteSpace([string]$config.rule_version) -or
        $null -eq $config.PSObject.Properties['rules'] -or
        -not ($config.rules -is [System.Array])) {
        throw "Category classification config is invalid: $Path"
    }
}

function Import-BestSellersCategoryRegistry {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Path)

    $registryPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        throw "Category Registry does not exist: $registryPath"
    }

    $json = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 -ErrorAction Stop
    $schemaPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config\schemas\category-registry.schema.json'))
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "Category Registry schema does not exist: $schemaPath"
    }

    $schemaErrors = @()
    try {
        $testJson = Get-Command -Name Test-Json -CommandType Cmdlet -ErrorAction SilentlyContinue
        if ($null -ne $testJson) {
            $schemaValid = $json | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable +schemaErrors
        }
        else {
            # Windows PowerShell 5.1 does not ship Test-Json. The strict
            # structural checks below still validate the registry contract;
            # keep the loader usable for scheduled tasks running on 5.1.
            $null = $json | ConvertFrom-Json -ErrorAction Stop
            $schemaValid = $true
        }
    }
    catch {
        throw "Category Registry schema validation failed: $($_.Exception.Message)"
    }
    if (-not $schemaValid) {
        throw 'Category Registry schema validation failed.'
    }

    try {
        $raw = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Category Registry is not valid JSON: $registryPath"
    }
    if ([string]$raw.schema_version -cne 'category-registry-v1') {
        throw 'Unsupported Category Registry schema version.'
    }

    $projectRoot = Resolve-CategoryRegistryProjectRoot -RegistryPath $registryPath
    $categoryKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $nodeIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $categories = [System.Collections.Generic.List[object]]::new()

    foreach ($category in @($raw.categories)) {
        $categoryKey = [string]$category.category_key
        $nodeId = [string]$category.amazon_node_id
        if (-not $categoryKeys.Add($categoryKey)) {
            throw "Category Registry contains duplicate category key: $categoryKey"
        }
        if (-not $nodeIds.Add($nodeId)) {
            throw "Category Registry contains duplicate Amazon node: $nodeId"
        }

        $classificationPath = Resolve-CategoryRegistryReference -ProjectRoot $projectRoot -Reference ([string]$category.classification_config_path) -Description 'Category classification config'
        $attributePath = Resolve-CategoryRegistryReference -ProjectRoot $projectRoot -Reference ([string]$category.attribute_schema_path) -Description 'Category attribute schema'
        Assert-CategoryRegistryClassificationConfig -Path $classificationPath
        $attributeSchema = Read-CategoryRegistryAttributeSchema -Path $attributePath
        $attributeTypes = @($attributeSchema.product_types.PSObject.Properties.Name)

        $segmentKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $segments = [System.Collections.Generic.List[object]]::new()
        foreach ($segment in @($category.segments)) {
            $segmentKey = [string]$segment.key
            if (-not $segmentKeys.Add($segmentKey)) {
                throw "Category '$categoryKey' contains duplicate segment key: $segmentKey"
            }
            foreach ($productType in @($segment.product_types)) {
                if ([string]$productType -cnotin $attributeTypes) {
                    throw "Category '$categoryKey' segment '$segmentKey' references an unknown product type: $productType"
                }
            }
            $segments.Add([pscustomobject][ordered]@{
                Key = $segmentKey
                LabelZh = [string]$segment.label_zh
                ProductTypes = @($segment.product_types | ForEach-Object { [string]$_ })
            })
        }

        foreach ($defaultProperty in @($category.defaults.PSObject.Properties)) {
            if (-not $segmentKeys.Contains([string]$defaultProperty.Value)) {
                throw "Category '$categoryKey' has invalid default segment '$($defaultProperty.Value)' for page '$($defaultProperty.Name)'."
            }
        }

        $normalizedDefaults = [ordered]@{}
        foreach ($defaultProperty in @($category.defaults.PSObject.Properties)) {
            $normalizedDefaults[$defaultProperty.Name] = [string]$defaultProperty.Value
        }
        $categories.Add([pscustomobject][ordered]@{
            CategoryKey = $categoryKey
            Slug = [string]$category.slug
            LabelZh = [string]$category.label_zh
            LabelEn = [string]$category.label_en
            NodeId = $nodeId
            SourceUrl = [string]$category.source_url
            TargetCount = [int]$category.target_count
            Enabled = [bool]$category.enabled
            ReportFileToken = [string]$category.report_file_token
            ClassificationConfigPath = $classificationPath
            AttributeSchemaPath = $attributePath
            Segments = @($segments.ToArray())
            Defaults = [pscustomobject]$normalizedDefaults
        })
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$raw.schema_version
        Marketplace = [pscustomobject][ordered]@{
            ContextCode = [string]$raw.marketplace.context_code
            StorageCode = [string]$raw.marketplace.storage_code
        }
        PageLoading = [pscustomobject][ordered]@{
            top_30_rule = [string]$raw.page_loading.top_30_rule
            pagination_rule = [string]$raw.page_loading.pagination_rule
        }
        Path = $registryPath
        ProjectRoot = $projectRoot
        Categories = @($categories.ToArray())
    }
}

function Get-BestSellersCategoryKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Registry,
        [switch]$EnabledOnly
    )

    if ($null -eq $Registry -or $null -eq $Registry.PSObject.Properties['Categories']) {
        throw 'A normalized Category Registry is required.'
    }
    foreach ($category in @($Registry.Categories)) {
        if (-not $EnabledOnly -or $category.Enabled) {
            Write-Output ([string]$category.CategoryKey)
        }
    }
}

function Get-BestSellersCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Registry,
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [switch]$AllowDisabled
    )

    if ($null -eq $Registry -or $null -eq $Registry.PSObject.Properties['Categories']) {
        throw 'A normalized Category Registry is required.'
    }
    $matches = @($Registry.Categories | Where-Object { [string]$_.CategoryKey -ceq $CategoryKey })
    if ($matches.Count -ne 1 -or (-not $AllowDisabled -and -not $matches[0].Enabled)) {
        throw "Unknown or disabled category key: $CategoryKey"
    }
    return $matches[0]
}

Export-ModuleMember -Function Import-BestSellersCategoryRegistry, Get-BestSellersCategoryKeys, Get-BestSellersCategory
