# Dragonfly Client

Infra configuration for the Dragonfly client. We're currently using the [Dragonfly Rust client](https://github.com/vipyrsec/dragonfly-client-rs).

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called `dragonfly-client-secrets`.


| Environment     | Description                   |
|-----------------|-------------------------------|
| CLIENT_ID       | Part of the OAUTH credentials |
| CLIENT_SECRET   | Part of the OAUTH credentials |
| USERNAME        | Part of the OAUTH credentials |
| PASSWORD        | Part of the OAUTH credentials |
