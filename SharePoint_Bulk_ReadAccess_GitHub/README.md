# Bulk Read access on SharePoint Online with PnP PowerShell

A safety-first PowerShell workflow for verifying and granting **explicit Read access** to one user across multiple SharePoint Online sites.

The script deliberately separates **verification** from **changes**:

1. `Verify` checks every site and writes a CSV report without modifying permissions.
2. `GrantMissing` adds Read only where the verification reports it missing.
3. Every grant is checked again with `Get-PnPWebPermission`.

## Why use a CSV instead of scraping a SharePoint page?

Modern SharePoint pages store Quick Links in internal JSON that can change depending on page version, localization and web-part structure. A reviewed CSV is simpler to audit, version and reuse:

```csv
Title;Url
Project A;https://contoso.sharepoint.com/sites/ProjectA
Project B;https://contoso.sharepoint.com/sites/Portfolio/ProjectB
```

## Repository structure

```text
.
├── Manage-SharePointReadAccess.ps1
├── Start-SharePointReadAccess.ps1
├── Start-SharePointReadAccess.cmd
├── config.example.psd1
├── sites.example.csv
├── SECURITY.md
└── README.md
```

## Requirements

- PowerShell 7.4 or later
- `PnP.PowerShell`
- An Entra application registration that can be used by `Connect-PnPOnline -Interactive`
- An operator account allowed to manage permissions on the target sites

Install the module:

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
```

## Setup

1. Copy `config.example.psd1` to `config.psd1`.
2. Set the Entra **Application (client) ID**.
3. Copy `sites.example.csv` to `sites.csv` and replace the sample URLs.
4. Keep the CSV header exactly as `Title;Url`.

Example configuration:

```powershell
@{
    ClientId = '00000000-0000-0000-0000-000000000000'
    SitesCsv = 'sites.csv'
    ExpectedSiteCount = 12
}
```

`ExpectedSiteCount` is a guardrail. The script stops before making changes when the CSV count differs from the expected value. Set it to `0` to disable the check.

## Usage

Interactive launcher:

```text
Start-SharePointReadAccess.cmd
```

Direct verification:

```powershell
./Manage-SharePointReadAccess.ps1 `
  -UserEmail 'user@contoso.com' `
  -SitesCsv './sites.csv' `
  -ClientId '00000000-0000-0000-0000-000000000000' `
  -Mode Verify
```

Grant only missing Read permissions:

```powershell
./Manage-SharePointReadAccess.ps1 `
  -UserEmail 'user@contoso.com' `
  -SitesCsv './sites.csv' `
  -ClientId '00000000-0000-0000-0000-000000000000' `
  -Mode GrantMissing
```

## Output

Each run writes a semicolon-delimited CSV under `Reports` with:

- site URL and title;
- roles detected before the operation;
- action performed;
- roles detected afterwards;
- errors and diagnostic details.

## Operational rules

- Always run `Verify` first.
- Review the CSV before running `GrantMissing`.
- Do not commit tenant URLs, user addresses, internal site names or production client IDs to a public repository.
- Test on a small non-production site set before wider use.
- This tool checks **explicit web-level permissions**. Access inherited through Microsoft 365 groups, SharePoint groups or parent webs may require a separate review.

## Lessons learned

- Do not treat the absence of a REST property as proof that a permission command failed.
- Use the official PnP verification command after `Set-PnPWebPermission`.
- Keep verification and mutation as separate modes.
- Keep the site list explicit and version-controlled.
- Generate a report for every execution.

## Disclaimer

Review the script and test it in your own tenant. Permission models differ between site collections, subsites, SharePoint groups and Microsoft 365 groups.
