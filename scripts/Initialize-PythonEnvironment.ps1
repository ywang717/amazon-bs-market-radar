param(
    [switch]$Recreate,
    [switch]$SkipDependencyInstall,
    [scriptblock]$PythonInvoker
)

$ErrorActionPreference = 'Stop'
function Invoke-ProjectPython {
    param(
        [Parameter(Mandatory = $true)][string]$PythonPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if ($null -ne $PythonInvoker) {
        return [pscustomobject]@{ Output = @(& $PythonInvoker $PythonPath @Arguments); ExitCode = 0 }
    }
    $output = & $PythonPath @Arguments
    return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Force
$runtime = Get-ProjectRuntimeSettings -ProjectRoot $projectRoot
$basePython = $runtime.BootstrapPythonPath
$venvRoot = $runtime.VenvRoot
$venvPython = $runtime.VenvPythonPath
if (-not (Test-Path -LiteralPath $basePython -PathType Leaf)) { throw "Project bootstrap Python not found: $basePython" }
if ($Recreate -and (Test-Path -LiteralPath $venvRoot)) {
    $resolved = (Resolve-Path -LiteralPath $venvRoot).Path
    if (-not $resolved.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected virtual environment path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if (-not (Test-Path -LiteralPath $venvPython)) {
    $creation = Invoke-ProjectPython -PythonPath $basePython -Arguments @('-m', 'venv', $venvRoot)
    if ($creation.ExitCode -ne 0) { throw "Python virtual environment creation failed with exit code $($creation.ExitCode)" }
}
if (-not $SkipDependencyInstall) {
    $installation = Invoke-ProjectPython -PythonPath $venvPython -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--requirement', (Join-Path $projectRoot 'requirements-pdf.txt'))
    if ($installation.ExitCode -ne 0) { throw "Python PDF dependency installation failed with exit code $($installation.ExitCode)" }
}
$validation = Invoke-ProjectPython -PythonPath $venvPython -Arguments @('-c', "import importlib.metadata as metadata,json,sys,reportlab,pdfplumber,pypdf,pypdfium2; print(json.dumps({'python':sys.version.split()[0],'reportlab':reportlab.Version,'pdfplumber':pdfplumber.__version__,'pypdf':pypdf.__version__,'pypdfium2':str(pypdfium2.PYPDFIUM_INFO),'playwright':metadata.version('playwright')}))")
if ($validation.ExitCode -ne 0) { throw 'Python PDF dependency validation failed.' }
$versions = $validation.Output | ConvertFrom-Json
$playwrightVersion = $null
if (-not [version]::TryParse([string]$versions.playwright, [ref]$playwrightVersion) -or $playwrightVersion -lt [version]'1.62.0') {
    throw 'Playwright 1.62.0 or newer is required for the supported system browser runtime.'
}
[pscustomobject]@{
    Status = 'READY'; PythonPath = (Resolve-Path -LiteralPath $venvPython).Path
    PythonVersion = $versions.python; ReportLabVersion = $versions.reportlab
    PdfPlumberVersion = $versions.pdfplumber; PyPdfVersion = $versions.pypdf
    PyPdfium2Version = $versions.pypdfium2; PlaywrightVersion = $versions.playwright
    UsesBundledSystemPackages = $false
} | ConvertTo-Json -Depth 3
