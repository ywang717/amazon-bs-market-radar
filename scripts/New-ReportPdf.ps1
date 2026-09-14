param(
    [Parameter(Mandatory = $true)][string]$MarkdownPath,
    [Parameter(Mandatory = $true)][string]$PdfPath,
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$GeneratedAtBeijing,
    [switch]$KeepRenderedPages
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Force
$runtime = Get-ProjectRuntimeSettings -ProjectRoot $projectRoot
$python = $runtime.VenvPythonPath
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Project Python virtual environment not found: $python" }
if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) { throw "Markdown report not found: $MarkdownPath" }
if ([string]::IsNullOrWhiteSpace($GeneratedAtBeijing)) {
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
    $GeneratedAtBeijing = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone).ToString('yyyy-MM-dd HH:mm')
}
$renderer = Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py'
$pythonArguments = @($renderer, '--markdown', $MarkdownPath, '--pdf', $PdfPath, '--title', $Title, '--generated-at-beijing', $GeneratedAtBeijing, '--verify-pdf')
if ($KeepRenderedPages) {
    $renderDirectory = Join-Path (Join-Path $projectRoot 'tmp\pdfs') ([Guid]::NewGuid().ToString('N'))
    $pythonArguments += @('--render-directory', $renderDirectory)
}
$resultJson = & $python @pythonArguments
if ($LASTEXITCODE -ne 0) { throw "PDF generation or verification failed with exit code $LASTEXITCODE" }
$result = $resultJson | ConvertFrom-Json
$renderedPaths = @()
if ($KeepRenderedPages) {
    $renderedPaths = @(Get-ChildItem -LiteralPath $renderDirectory -Filter 'page-*.png' | Sort-Object Name | ForEach-Object { $_.FullName })
    if ($renderedPaths.Count -ne [int]$result.page_count) { throw "PDF rendered page count mismatch: expected $($result.page_count), found $($renderedPaths.Count)" }
}
[pscustomobject]@{
    Status = 'VERIFIED'; PdfPath = (Resolve-Path -LiteralPath $PdfPath).Path
    PageCount = [int]$result.page_count; SizeBytes = [long]$result.size_bytes
    GeneratedAtBeijing = $GeneratedAtBeijing
    RenderedPages = if ($KeepRenderedPages) { $renderedPaths } else { @() }
} | ConvertTo-Json -Depth 4
