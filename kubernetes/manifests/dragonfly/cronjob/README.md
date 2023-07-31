# Dragonfly Cronjob 

Infra configuration for the [Dragonfly Functions](https://github.com/vipyrsec/dragonfly-functions).

## Secrets
This deployment expects a number of secrets and environment variables to exist in a secret called `dragonfly-cronjob-env`.


| Environment             | Description                                              |
|-------------------------|----------------------------------------------------------|
| BASE_URL                | Base URL of the Dragonfly API                            |
| AUTH0_DOMAIN            | Domain of the AUTH0 authentication server                |
| CLIENT_ID               | Client ID                                                |
| CLIENT_SECRET           | Client secret                                            |
| USERNAME                | Username                                                 |
| PASSWORD                | Password                                                 |
| AUDIENCE                | Authentication audience
