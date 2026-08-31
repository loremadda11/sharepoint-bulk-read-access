# SharePoint Bulk Read Access

PowerShell toolkit to verify and grant explicit Read access across multiple SharePoint Online sites using PnP PowerShell, CSV input, dry-run/verification logic and audit reports.

> **Portfolio context** — A sanitized example of how I approach repetitive IT operations: understand the access problem, define a safer repeatable workflow, automate the execution and keep verification separate from changes.

## The problem

Granting the same user access across many SharePoint sites manually means opening each site, checking existing permissions, applying changes and verifying the result one by one. That is slow, repetitive and easy to execute inconsistently.

## Solution

The toolkit separates the workflow into two clear modes:

1. **Verify** — checks every target site and writes a CSV report without changing permissions.
2. **GrantMissing** — grants Read only where verification reports it missing, then checks the result again.

```text
Reviewed CSV site list
        ↓
Verify current access
        ↓
CSV report
        ↓
Grant only missing Read access
        ↓
Verify again
        ↓
Audit report
```

## My role

- mapped the repetitive multi-site access workflow;
- defined a verification-first operating model;
- used AI-assisted development tools alongside PowerShell to accelerate implementation while reviewing and testing the resulting logic;
- added configuration guardrails, reporting and post-change verification;
- kept tenant-specific information out of the public version of the project.

## Practical impact

The workflow reduces repeated manual navigation across SharePoint sites and gives the operator a consistent process with a clear before/after report instead of relying on memory or one-off UI changes.

## Project files

The implementation is currently under [`SharePoint_Bulk_ReadAccess_GitHub/`](./SharePoint_Bulk_ReadAccess_GitHub/), including:

- `Manage-SharePointReadAccess.ps1`
- `Start-SharePointReadAccess.ps1`
- `Start-SharePointReadAccess.cmd`
- `config.example.psd1`
- `sites.example.csv`
- `SECURITY.md`
- detailed project `README.md`

## Technologies

`PowerShell 7` · `PnP PowerShell` · `SharePoint Online` · `Microsoft Entra ID` · `CSV reporting`

## Design principles

- verification before mutation;
- explicit reviewed input instead of scraping unstable page data;
- post-change validation;
- auditable CSV output;
- no real tenant URLs, identities or production configuration in the public repository;
- small test scope before wider execution.

## More details

See the [full technical README](./SharePoint_Bulk_ReadAccess_GitHub/README.md) for setup, usage, operational rules and lessons learned.
