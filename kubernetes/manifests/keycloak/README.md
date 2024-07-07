# Keycloak

[Keycloak](https://www.keycloak.org/) configuration

## Secrets
This deployment expects a number of secrets and environment variables to exist in a secret called `keycloak-secrets`.

Keycloak hostname configuration documentation: https://www.keycloak.org/server/hostname
Keycloak database configuration documentation: https://www.keycloak.org/server/db#_relevant_options


| Environment                 | Description                        |
|-----------------------------|------------------------------------|
| KEYCLOAK_ADMIN              | Keycloak Admin Panel Username      |
| KEYCLOAK_PASSWORD           | Keycloak Admin Panel Password      |
| KC_DB                       | Keycloak Database (e.g postgres)   |
| KC_DB_URL_HOST              | Keycloak database host             |
| KC_DB_URL_PORT              | Keycloak database port             |
| KC_DB_USERNAME              | Keycloak database username         |
| KC_DB_PASSWORD              | Keycloak database password         |
| KC_DB_URL_DATABASE          | Keycloak database name             |
| KC_HOSTNAME                 | Keycloak hostname                  |
