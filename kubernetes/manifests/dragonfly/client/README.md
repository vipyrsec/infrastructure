# Dragonfly Client

Infra configuration for the Dragonfly client. We're currently using the
[Dragonfly Rust client](https://github.com/vipyrsec/dragonfly-client-rs).

## Secrets

This deployment expects its environment variables to exist in a secret called
`dragonfly-client-env`.

| Environment                           | Description                                                  |
| ------------------------------------- | ------------------------------------------------------------ |
| DRAGONFLY_BASE_URL                    | Environment-specific public Dragonfly API URL                |
| DRAGONFLY_CF_ACCESS_CLIENT_ID         | Environment-specific Cloudflare Access service-token ID      |
| DRAGONFLY_CF_ACCESS_CLIENT_SECRET     | Environment-specific Cloudflare Access service-token secret  |

The staging secret must use `https://dragonfly-staging.vipyrsec.com`; the
production secret must use `https://dragonfly.vipyrsec.com`. The two service
tokens must be distinct.
