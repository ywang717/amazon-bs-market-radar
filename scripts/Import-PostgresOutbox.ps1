param(
    [Parameter(Mandatory = $true)][string]$OutboxPath,
    [string]$PsqlPath = 'psql'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\PostgresOutbox.psm1') -Force
Invoke-PostgresOutboxImport -OutboxPath $OutboxPath -PsqlPath $PsqlPath

