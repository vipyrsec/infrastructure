# Grafana

We use Grafana to display our metrics and logs from across our infrastructure.

The Grafana deployment expects a secret named `grafana-secret-env` with the following contents:

| Environment Variable         | Description                                         |
|------------------------------|-----------------------------------------------------|
| GF_AUTH_GITHUB_CLIENT_ID     | The client ID of the Github app to use for auth     |
| GF_AUTH_GITHUB_CLIENT_SECRET | The client secret of the Github app to use for auth |
| GF_SECURITY_ADMIN_PASSWORD   | The admin password the the grafana admin console    |
