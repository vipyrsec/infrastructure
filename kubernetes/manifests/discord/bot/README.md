# Bot

Infra configuration for the Discord bot.

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called `bot-env`.


| Environment | Description               |
| ----------- | ------------------------- |
| BOT_TOKEN   | Auth token for Discord    |
| SENTRY_DSN  | Connection DSN for Sentry |
