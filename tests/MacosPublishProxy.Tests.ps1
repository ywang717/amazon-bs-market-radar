$projectRoot = Split-Path -Parent $PSScriptRoot
Describe 'macOS publish uses configured system proxy without overriding explicit configuration' {
    It 'discovers the system proxy for the child publisher and preserves an explicit proxy' -Skip:([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $root = Join-Path $TestDrive 'project'
        foreach ($dir in @('scripts','.local/powershell','.local/node/bin','var/amazon-bestsellers/2026-10-18')) { New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null }
        Copy-Item (Join-Path $projectRoot 'scripts/Publish-MacosDashboard.sh') (Join-Path $root 'scripts/Publish-MacosDashboard.sh')
        Set-Content (Join-Path $root '.local/dashboard-sync-secret') 'dummy-audit-secret'
        Set-Content (Join-Path $root 'var/amazon-bestsellers/2026-10-18/best-sellers-capture-receipt.json') '{}'
        Set-Content (Join-Path $root '.local/node/bin/python3') "#!/bin/sh`nprintf '%s' 'http://127.0.0.1:19000'"
        Set-Content (Join-Path $root '.local/powershell/pwsh') '#!/bin/sh' , 'printf "%s|%s" "$HTTPS_PROXY" "$HTTP_PROXY"'
        & chmod +x (Join-Path $root '.local/node/bin/python3') (Join-Path $root '.local/powershell/pwsh')
        $saved = @{}
        foreach ($name in @('HTTPS_PROXY','https_proxy','HTTP_PROXY','http_proxy')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,$null,'Process') }
        try {
            $actual = & /bin/sh (Join-Path $root 'scripts/Publish-MacosDashboard.sh')
            $LASTEXITCODE | Should Be 0
            $actual | Should Be 'http://127.0.0.1:19000|http://127.0.0.1:19000'
            $env:HTTPS_PROXY='http://configured.example:9000'; $env:HTTP_PROXY='http://configured.example:9001'
            (& /bin/sh (Join-Path $root 'scripts/Publish-MacosDashboard.sh')) | Should Be 'http://configured.example:9000|http://configured.example:9001'
        } finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') } }
    }
}
