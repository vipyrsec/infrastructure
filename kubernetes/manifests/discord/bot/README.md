# Bot

Infra configuration for the Discord bot.

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called `bot-env`.


| Environment         | Description                         |
| ------------------- | ----------------------------------- |
| BOT_TOKEN           | Auth token for Discord              |
| SENTRY_DSN          | Connection DSN for Sentry           |
| ALLOWED_ROLES       | Allowed roles for the bot to assign |
| AUTH0_USERNAME      | Username for Auth0                  |
| AUTH0_PASSWORD      | Password for Auth0                  |
| AUTH0_CLIENT_ID     | Client ID for Auth0                 |
| AUTH0_CLIENT_SECRET | Client secret for Auth0             |
    