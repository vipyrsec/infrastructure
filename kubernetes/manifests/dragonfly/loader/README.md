# Dragonfly Loader

Infra configuration for the [Dragonfly Loader](https://github.com/vipyrsec/dragonfly-loader).

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called
`dragonfly-loader-env`.

| Environment             | Description                                                  |
| ----------------------- | ------------------------------------------------------------ |
| BASE_URL                | Environment-specific public Dragonfly API URL                |
| CF_ACCESS_CLIENT_ID     | Environment-specific Cloudflare Access service-token ID      |
| CF_ACCESS_CLIENT_SECRET | Environment-specific Cloudflare Access service-token secret  |

The staging secret must use `https://dragonfly-staging.vipyrsec.com`; the
production secret must use `https://dragonfly.vipyrsec.com`. Never copy either
environment's service-token pair into the other cluster.
