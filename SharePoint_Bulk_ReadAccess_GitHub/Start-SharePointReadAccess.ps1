[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MainScript = Join-Path $PSScriptRoot 'Manage-SharePointReadAccess.ps1'

if (-not (Test-Path -LiteralPath $MainScript)) {
    throw "Main script not found: $MainScript"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$Config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$DefaultCsv = Join-Path $PSScriptRoot ([string]$Config.SitesCsv)

Write-Host ''
Write-Host 'SharePoint bulk Read access' -ForegroundColor Cyan
Write-Host '1 - Verify only (safe, no changes)'
Write-Host '2 - Grant Read only where missing'
Write-Host ''

$UserEmail = Read-Host 'User e-mail'
if ([string]::IsNullOrWhiteSpace($UserEmail)) {
    throw 'User e-mail is required.'
}

$Choice = Read-Host 'Choose 1 or 2'

switch ($Choice) {
    '1' {
        $Mode = 'Verify'
    }
    '2' {
        $Confirm = Read-Host 'Type GRANT to continue'
        if ($Confirm -ne 'GRANT') {
            Write-Host 'Operation cancelled.' -ForegroundColor Yellow
            return
        }
        $Mode = 'GrantMissing'
    }
    default {
        throw 'Invalid choice.'
    }
}

& $MainScript `
    -UserEmail $UserEmail `
    -SitesCsv $DefaultCsv `
    -ClientId ([guid]$Config.ClientId) `
    -Mode $Mode `
    -ExpectedSiteCount ([int]$Config.ExpectedSiteCount)
