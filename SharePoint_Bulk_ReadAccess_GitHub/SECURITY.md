# Security notes

- Never commit production tenant URLs, internal project names or user e-mail addresses to a public repository.
- An Entra application client ID is not a secret, but publishing it may reveal internal application structure. Use a placeholder in public examples.
- Do not store client secrets, certificates or passwords in the script or CSV.
- Use interactive authentication or a properly secured certificate-based application for unattended execution.
- Restrict the operator account and Entra application to the permissions required for the task.
- Run verification before any permission change and retain the generated report.
