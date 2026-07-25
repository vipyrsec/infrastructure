# Bot

Infra configuration for the Discord bot.

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called `bot-env`.

| Environment             | Description                                                  |
| ----------------------- | ------------------------------------------------------------ |
| BOT_TOKEN               | Authentication token for Discord                             |
| SENTRY_DSN              | Connection DSN for Sentry                                    |
| ALLOWED_ROLES           | Roles the bot may assign                                     |
| DRAGONFLY_API_URL       | Environment-specific public Dragonfly API URL                |
| CF_ACCESS_CLIENT_ID     | Environment-specific Cloudflare Access service-token ID      |
| CF_ACCESS_CLIENT_SECRET | Environment-specific Cloudflare Access service-token secret  |

Staging and production must use separate service tokens and API URLs.
Each bot reads the cached `/queue-status` endpoint from its own
`DRAGONFLY_API_URL`, so bot commands do not query PostgreSQL.
