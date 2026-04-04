# Dragonfly Loader

Infra configuration for the [Dragonfly Loader](https://github.com/vipyrsec/dragonfly-loader).

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called
`dragonfly-loader-env`.

| Environment   | Description                               |
| ------------- | ----------------------------------------- |
| BASE_URL      | Base URL of the Dragonfly API             |
| CF_ACCESS_CLIENT_ID | Cloudflare Access service token client ID |
| CF_ACCESS_CLIENT_SECRET | Cloudflare Access service token client secret |

For staging, `BASE_URL` should be the public protected hostname
`https://dragonfly-staging.vipyrsec.com`.
