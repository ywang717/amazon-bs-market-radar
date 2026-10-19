$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src/DashboardPublishHttp.psm1') -Force
Describe 'Portable dashboard HTTP executable selection' {
    It 'falls back to the native curl application when curl.exe is absent' {
        Mock Get-Command -ModuleName DashboardPublishHttp -ParameterFilter { $Name -eq 'curl.exe' } { return $null }
        Mock Get-Command -ModuleName DashboardPublishHttp -ParameterFilter { $Name -eq 'curl' } { return [pscustomobject]@{ Source = '/audit/native/curl' } }
        Get-DashboardPublishCurlExecutable | Should Be '/audit/native/curl'
    }
    It 'retains the Windows executable when available' {
        Mock Get-Command -ModuleName DashboardPublishHttp -ParameterFilter { $Name -eq 'curl.exe' } { return [pscustomobject]@{ Source = 'C:\Windows\curl.exe' } }
        Get-DashboardPublishCurlExecutable | Should Be 'C:\Windows\curl.exe'
    }
}
