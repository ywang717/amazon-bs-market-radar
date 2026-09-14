Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Copy-BestSellersReportToDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [Parameter(Mandatory = $true)][ValidateSet('Daily', 'Weekly')][string]$ReportKind,
        [string]$CategoryKey,
        [string]$ArchiveRoot,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if (-not (Test-Path -LiteralPath $PdfPath -PathType Leaf -ErrorAction Stop)) {
        throw "Source PDF not found: $PdfPath"
    }

    $sourcePath = (Resolve-Path -LiteralPath $PdfPath -ErrorAction Stop).Path
    if (-not [string]::Equals([IO.Path]::GetExtension($sourcePath), '.pdf', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Report source must be a PDF: $PdfPath"
    }

    if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        $ArchiveRoot = Join-Path $desktopPath '亚马逊bs榜单每日监控'
    }
    else {
        $ArchiveRoot = [IO.Path]::GetFullPath($ArchiveRoot)
    }

    if ($ReportKind -eq 'Daily') {
        $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
        try { $category = Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey }
        catch { throw "Unknown daily category key: $CategoryKey" }
        $targetDirectory = Join-Path $ArchiveRoot ([string]$category.LabelZh)
    }
    else {
        $targetDirectory = Join-Path $ArchiveRoot '周报'
    }

    New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop | Out-Null
    $destinationPath = Join-Path $targetDirectory ([IO.Path]::GetFileName($sourcePath))
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -ErrorAction Stop
    return (Resolve-Path -LiteralPath $destinationPath -ErrorAction Stop).Path
}

Export-ModuleMember -Function Copy-BestSellersReportToDesktop

