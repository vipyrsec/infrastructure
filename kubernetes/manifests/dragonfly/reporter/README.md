# Dragonfly Reporter

Infra configuration for the [Dragonfly Reporter](https://github.com/vipyrsec/dragonfly-reporter).

## Secrets
This deployment expects a number of secrets and environment variables to exist in a secret called `dragonfly-reporter-secrets`.


| Environment             | Description                                 |
|-------------------------|---------------------------------------------|
| OBSERVATION_API_TOKEN   | The auth token for PyPI's Obeservations API |
