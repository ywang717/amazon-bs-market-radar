param([switch]$ProcessOnly)

$ErrorActionPreference = 'Stop'
$clientId = Read-Host 'Enter AMAZON_CREATORS_CLIENT_ID'
$secureClientSecret = Read-Host 'Enter AMAZON_CREATORS_CLIENT_SECRET' -AsSecureString
$partnerTag = Read-Host 'Enter AMAZON_CREATORS_PARTNER_TAG'
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureClientSecret)
    $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    foreach ($item in @(
        [pscustomobject]@{ Name = 'Client ID'; Value = $clientId },
        [pscustomobject]@{ Name = 'Client secret'; Value = $clientSecret },
        [pscustomobject]@{ Name = 'Partner tag'; Value = $partnerTag }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Value)) { throw "$($item.Name) cannot be empty." }
        if ([string]$item.Value -match '[<>]') { throw "$($item.Name) must not contain angle brackets." }
        if ([string]$item.Value -match '[\r\n]') { throw "$($item.Name) must be a single line." }
    }

    $values = [ordered]@{
        AMAZON_CREATORS_CLIENT_ID = $clientId.Trim()
        AMAZON_CREATORS_CLIENT_SECRET = $clientSecret
        AMAZON_CREATORS_PARTNER_TAG = $partnerTag.Trim()
    }
    foreach ($name in $values.Keys) {
        [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'Process')
        if (-not $ProcessOnly) { [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'User') }
    }

    [pscustomobject]@{
        Status = 'CONFIGURED'
        Scope = if ($ProcessOnly) { 'Process' } else { 'ProcessAndCurrentUser' }
        ClientIdConfigured = $true
        ClientSecretConfigured = $true
        PartnerTagConfigured = $true
    } | Format-List
}
finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    Remove-Variable clientSecret,secureClientSecret -ErrorAction SilentlyContinue
}
