param(
    [string]$Username = '746254487@qq.com',
    [switch]$ProcessOnly
)

$ErrorActionPreference = 'Stop'
$secureAuthCode = Read-Host 'Enter the NEW QQ SMTP authorization code' -AsSecureString
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAuthCode)
    $authCode = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($authCode)) { throw 'SMTP authorization code cannot be empty.' }
    if ($authCode.Contains('<') -or $authCode.Contains('>')) { throw 'Enter the authorization code without angle brackets.' }

    [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_USERNAME', $Username, 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE', $authCode, 'Process')
    if (-not $ProcessOnly) {
        [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_USERNAME', $Username, 'User')
        [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE', $authCode, 'User')
    }

    [pscustomobject]@{
        Status = 'CONFIGURED'
        Username = $Username
        Scope = if ($ProcessOnly) { 'Process' } else { 'ProcessAndCurrentUser' }
        AuthorizationCodeStored = $true
    } | Format-List
}
finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    Remove-Variable authCode -ErrorAction SilentlyContinue
    Remove-Variable secureAuthCode -ErrorAction SilentlyContinue
}
