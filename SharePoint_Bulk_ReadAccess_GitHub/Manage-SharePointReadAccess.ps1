#requires -Version 7.4
#requires -Modules PnP.PowerShell

<#
.SYNOPSIS
    Verifies and optionally grants explicit Read permission to one user
    across multiple SharePoint Online sites listed in a CSV file.

.DESCRIPTION
    Safety-first workflow:
      - Verify: reads current explicit web permissions only.
      - GrantMissing: grants Read only where it is not already present,
        then verifies the result with Get-PnPWebPermission.

    A CSV report is generated for every run.

.CSV FORMAT
    Title;Url
    Project A;https://contoso.sharepoint.com/sites/ProjectA
    Project B;https://contoso.sharepoint.com/sites/Portfolio/ProjectB

.EXAMPLE
    .\Manage-SharePointReadAccess.ps1 `
        -UserEmail "user@contoso.com" `
        -SitesCsv ".\sites.csv" `
        -ClientId "00000000-0000-0000-0000-000000000000" `
        -Mode Verify

.EXAMPLE
    .\Manage-SharePointReadAccess.ps1 `
        -UserEmail "user@contoso.com" `
        -SitesCsv ".\sites.csv" `
        -ClientId "00000000-0000-0000-0000-000000000000" `
        -Mode GrantMissing
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$UserEmail,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$SitesCsv,

    [Parameter(Mandatory)]
    [guid]$ClientId,

    [ValidateSet('Verify', 'GrantMissing')]
    [string]$Mode = 'Verify',

    [ValidateRange(0, 10000)]
    [int]$ExpectedSiteCount = 0,

    [string]$ReportDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'PowerShell 7.4 or later is required.'
}

if (-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
    throw @"
PnP.PowerShell is not installed.
Run:
Install-Module PnP.PowerShell -Scope CurrentUser
"@
}

Import-Module PnP.PowerShell -ErrorAction Stop

$SitesCsv = (Resolve-Path -LiteralPath $SitesCsv).Path

if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path (Split-Path $SitesCsv -Parent) 'Reports'
}

New-Item -Path $ReportDirectory -ItemType Directory -Force | Out-Null
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportPath = Join-Path $ReportDirectory "SharePoint_ReadAccess_$Timestamp.csv"

$Sites = @(Import-Csv -LiteralPath $SitesCsv -Delimiter ';')

if ($Sites.Count -eq 0) {
    throw 'The CSV does not contain any sites.'
}

$CsvHeaders = @($Sites[0].PSObject.Properties.Name)
foreach ($RequiredHeader in @('Title', 'Url')) {
    if ($CsvHeaders -notcontains $RequiredHeader) {
        throw "Missing CSV column: $RequiredHeader"
    }
}

if ($ExpectedSiteCount -gt 0 -and $Sites.Count -ne $ExpectedSiteCount) {
    throw "Expected $ExpectedSiteCount sites, found $($Sites.Count). No changes were made."
}

$DuplicateUrls = @(
    $Sites |
        Group-Object Url |
        Where-Object Count -gt 1
)

if ($DuplicateUrls.Count -gt 0) {
    throw 'The CSV contains duplicate URLs. No changes were made.'
}

$Results = [System.Collections.Generic.List[object]]::new()

function Connect-TargetSite {
    param([Parameter(Mandatory)][string]$Url)

    Connect-PnPOnline `
        -Url $Url `
        -Interactive `
        -ClientId $ClientId `
        -ValidateConnection
}

function Get-ReadRoleDefinition {
    $Role = Get-PnPRoleDefinition |
        Where-Object { [string]$_.RoleTypeKind -eq 'Reader' } |
        Select-Object -First 1

    if ($null -eq $Role) {
        throw 'The Read/Reader permission level was not found.'
    }

    return $Role
}

function Get-TargetUser {
    param(
        [Parameter(Mandatory)][string]$Email,
        [switch]$CreateWhenMissing
    )

    $User = Get-PnPUser |
        Where-Object {
            (
                -not [string]::IsNullOrWhiteSpace([string]$_.Email) -and
                [string]$_.Email -eq $Email
            ) -or
            (
                -not [string]::IsNullOrWhiteSpace([string]$_.LoginName) -and
                (
                    [string]$_.LoginName -eq $Email -or
                    [string]$_.LoginName -like "*|$Email"
                )
            )
        } |
        Select-Object -First 1

    if ($null -eq $User -and $CreateWhenMissing) {
        $User = New-PnPUser -LoginName $Email
    }

    return $User
}

function Get-ExplicitRoleDefinitions {
    param(
        [Parameter(Mandatory)]$Web,
        [Parameter(Mandatory)][int]$PrincipalId
    )

    try {
        return @(
            Get-PnPWebPermission `
                -Identity $Web `
                -PrincipalId $PrincipalId `
                -ErrorAction Stop
        )
    }
    catch {
        if ($_.Exception.Message -match '(?i)does not exist|not found|non esiste|non trovato') {
            return @()
        }

        throw
    }
}

function Test-ReadRole {
    param([object[]]$Roles)

    foreach ($Role in @($Roles)) {
        if (
            [string]$Role.RoleTypeKind -eq 'Reader' -or
            [string]$Role.Name -eq 'Read' -or
            [string]$Role.Name -eq 'Lettura'
        ) {
            return $true
        }
    }

    return $false
}

function Get-RoleNames {
    param([object[]]$Roles)

    return (
        @($Roles) |
            ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace([string]$_.Name)) {
                    [string]$_.Name
                }
                else {
                    [string]$_.RoleTypeKind
                }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    ) -join ', '
}

Write-Host ''
Write-Host "User: $UserEmail" -ForegroundColor Cyan
Write-Host "Sites: $($Sites.Count)" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor $(if ($Mode -eq 'Verify') { 'Yellow' } else { 'Red' })
Write-Host ''

$Index = 0

foreach ($Site in $Sites) {
    $Index++
    $Title = [string]$Site.Title
    $Url = [string]$Site.Url
    $SiteTitle = ''
    $StatusBefore = ''
    $RolesBeforeText = ''
    $Action = 'NONE'
    $StatusAfter = ''
    $RolesAfterText = ''
    $Detail = ''

    Write-Host "[$Index/$($Sites.Count)] $Title" -ForegroundColor Cyan
    Write-Host "  $Url" -ForegroundColor DarkGray

    try {
        $Uri = [uri]$Url
        if ($Uri.Scheme -ne 'https') {
            throw 'Only HTTPS SharePoint URLs are supported.'
        }

        Connect-TargetSite -Url $Url

        $Web = Get-PnPWeb -Includes Title,Url
        $SiteTitle = [string]$Web.Title
        $ReadRole = Get-ReadRoleDefinition
        $User = Get-TargetUser -Email $UserEmail

        if ($null -eq $User) {
            $RolesBefore = @()
        }
        else {
            $RolesBefore = @(
                Get-ExplicitRoleDefinitions `
                    -Web $Web `
                    -PrincipalId ([int]$User.Id)
            )
        }

        $HasReadBefore = Test-ReadRole -Roles $RolesBefore
        $RolesBeforeText = Get-RoleNames -Roles $RolesBefore
        $StatusBefore = if ($HasReadBefore) { 'READ_PRESENT' } else { 'READ_MISSING' }

        if ($HasReadBefore) {
            $StatusAfter = $StatusBefore
            $RolesAfterText = $RolesBeforeText
            $Detail = 'No change: Read was already present.'
            Write-Host "  OK: Read already present ($RolesBeforeText)" -ForegroundColor Green
        }
        elseif ($Mode -eq 'Verify') {
            $Action = 'WOULD_GRANT_READ'
            $StatusAfter = $StatusBefore
            $RolesAfterText = $RolesBeforeText
            $Detail = 'Verification only: no change was made.'
            Write-Host '  MISSING: explicit Read was not detected.' -ForegroundColor Yellow
        }
        else {
            if ($null -eq $User) {
                $User = Get-TargetUser -Email $UserEmail -CreateWhenMissing
            }

            $Action = 'GRANT_READ'
            Set-PnPWebPermission -User $UserEmail -AddRole ([string]$ReadRole.Name)
            Start-Sleep -Seconds 2

            $Web = Get-PnPWeb -Includes Title,Url
            $User = Get-TargetUser -Email $UserEmail

            if ($null -eq $User) {
                throw 'The user was not found after granting permission.'
            }

            $RolesAfter = @(
                Get-ExplicitRoleDefinitions `
                    -Web $Web `
                    -PrincipalId ([int]$User.Id)
            )

            $HasReadAfter = Test-ReadRole -Roles $RolesAfter
            $RolesAfterText = Get-RoleNames -Roles $RolesAfter
            $StatusAfter = if ($HasReadAfter) { 'READ_PRESENT' } else { 'READ_MISSING' }

            if (-not $HasReadAfter) {
                throw 'Set-PnPWebPermission completed, but Read was not detected during final verification.'
            }

            $Detail = 'Read granted and verified.'
            Write-Host '  OK: Read granted and verified.' -ForegroundColor Green
        }
    }
    catch {
        $StatusAfter = 'ERROR'
        $Detail = $_.Exception.Message
        Write-Host "  ERROR: $Detail" -ForegroundColor Red
    }

    $Results.Add(
        [pscustomobject]@{
            Date        = Get-Date
            User        = $UserEmail
            CsvTitle    = $Title
            Url         = $Url
            SiteTitle   = $SiteTitle
            Mode        = $Mode
            StatusBefore = $StatusBefore
            RolesBefore = $RolesBeforeText
            Action      = $Action
            StatusAfter = $StatusAfter
            RolesAfter  = $RolesAfterText
            Detail      = $Detail
        }
    )

    Write-Host ''
}

$Results |
    Export-Csv `
        -LiteralPath $ReportPath `
        -Delimiter ';' `
        -NoTypeInformation `
        -Encoding utf8BOM

$Present = @($Results | Where-Object StatusAfter -eq 'READ_PRESENT').Count
$Missing = @($Results | Where-Object StatusAfter -eq 'READ_MISSING').Count
$Errors = @($Results | Where-Object StatusAfter -eq 'ERROR').Count

Write-Host '========================================' -ForegroundColor Cyan
Write-Host "Sites processed: $($Results.Count)"
Write-Host "Read present:    $Present" -ForegroundColor Green
Write-Host "Read missing:    $Missing" -ForegroundColor Yellow
Write-Host "Errors:          $Errors" -ForegroundColor $(if ($Errors -gt 0) { 'Red' } else { 'Green' })
Write-Host "Report:          $ReportPath" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

Invoke-Item $ReportDirectory
