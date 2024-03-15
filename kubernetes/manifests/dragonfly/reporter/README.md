# Dragonfly Reporter

Infra configuration for the [Dragonfly Reporter](https://github.com/vipyrsec/dragonfly-reporter).

## Secrets
This deployment expects a number of secrets and environment variables to exist in a secret called `dragonfly-reporter-secrets`.


| Environment             | Description                        |
|-------------------------|----------------------------------- |
| PYPI_API_TOKEN          | PyPI user API token                |
| MICROSOFT_TENANT_ID     | MS tenant                          |
| MICROSOFT_CLIENT_ID     | MS client ID                       |
| MICROSOFT_CLIENT_SECRET | MS client secret                   |
| SENTRY_DSN              | DSN for reporting events to Sentry |
