# Dragonfly Mainframe

Infra configuration for the [Dragonfly Mainframe](https://github.com/vipyrsec/dragonfly-mainframe).

## Secrets

This deployment expects its environment variables to exist in a secret called
`dragonfly-mainframe-env`.

| Environment             | Description                                              |
| ----------------------- | -------------------------------------------------------- |
| CF_ACCESS_AUDIENCE      | Audience of this environment's Cloudflare Access app     |
| CF_ACCESS_TEAM_DOMAIN   | Cloudflare Access team-domain issuer                     |
| DB_URL                  | The database connection DSN                              |
| DRAGONFLY_GITHUB_TOKEN  | A GitHub PAT to access the Security Intelligence ruleset |
| EMAIL_RECIPIENT         | The default email recipient                              |
| MICROSOFT_TENANT_ID     | Part of the credentials for the mailer                   |
| MICROSOFT_CLIENT_ID     | Part of the credentials for the mailer                   |
| MICROSOFT_CLIENT_SECRET | Part of the credentials for the mailer                   |

Staging and production must use different Access application audiences.
`CF_ACCESS_TEAM_DOMAIN` may be shared because both applications belong to the
same Cloudflare Zero Trust tenant; application audiences and caller service
tokens must not be shared.
