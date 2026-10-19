Set-StrictMode -Version Latest

function Get-ProjectRuntimeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root not found: $ProjectRoot"
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $macRuntime = $PSVersionTable.ContainsKey("PSEdition") -and $PSVersionTable.PSEdition -eq "Core" -and $IsMacOS
    $bootstrapPython = Join-Path $resolvedRoot '.local\python\python.exe'
    $venvPython = Join-Path $resolvedRoot '.venv\Scripts\python.exe'
    if ($macRuntime) {
        $bootstrapPython = Join-Path $resolvedRoot '.local/python/bin/python3'
        if (-not (Test-Path -LiteralPath $bootstrapPython -PathType Leaf)) {
            $bootstrapPython = (Get-Command python3 -CommandType Application -ErrorAction Stop).Source
        }
        $venvPython = Join-Path $resolvedRoot '.venv/bin/python3'
    }
    [pscustomobject]@{
        ProjectRoot = $resolvedRoot
        LocalRoot = Join-Path $resolvedRoot '.local'
        BootstrapPythonPath = $bootstrapPython
        VenvRoot = Join-Path $resolvedRoot '.venv'
        VenvPythonPath = $venvPython
        PostgresSettingsPath = Join-Path $resolvedRoot '.local\postgres-settings.json'
        PostgresInstallRoot = Join-Path $resolvedRoot '.local\postgresql'
        PostgresDataRoot = Join-Path $resolvedRoot '.local\postgres-data'
    }
}

Export-ModuleMember -Function Get-ProjectRuntimeSettings
