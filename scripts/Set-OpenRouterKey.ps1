[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$secureKey = Read-Host 'Enter the OpenRouter API key (input is hidden)' -AsSecureString
if ($secureKey.Length -eq 0) {
    throw 'No key was entered.'
}

$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        throw 'The key is empty.'
    }
    [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY', $plainKey, 'User')
    [Environment]::SetEnvironmentVariable('TYPESAFE_API_KEY', $plainKey, 'User')
} finally {
    if ($pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    Remove-Variable plainKey -ErrorAction SilentlyContinue
}

Write-Host 'Saved OPENROUTER_API_KEY and TYPESAFE_API_KEY for the current Windows user.'
Write-Host 'Fully exit and restart Codex before expecting desktop processes to inherit the new values.'
