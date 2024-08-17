# Dragonfly Mainframe

Infra configuration for the [Dragonfly Mainframe](https://github.com/vipyrsec/dragonfly-mainframe).

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called
`dragonfly-mainframe-secrets`.

| Environment             | Description                                              |
| ----------------------- | -------------------------------------------------------- |
| DB_URL                  | The database connection DSN                              |
| DRAGONFLY_GITHUB_TOKEN  | A GitHub PAT to access the Security Intelligence ruleset |
| EMAIL_RECIPIENT         | The default email recipient                              |
| MICROSOFT_TENANT_ID     | Part of the credentials for the mailer                   |
| MICROSOFT_CLIENT_ID     | Part of the credentials for the mailer                   |
| MICROSOFT_CLIENT_SECRET | Part of the credentials for the mailer                   |
