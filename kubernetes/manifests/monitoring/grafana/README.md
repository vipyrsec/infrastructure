# Grafana

We use Grafana to display our metrics and logs from across our infrastructure.

The Grafana deployment expects a secret named `grafana-secret-env` with the following contents:

| Environment Variable         | Description                                         |
| ---------------------------- | --------------------------------------------------- |
| GF_AUTH_GITHUB_CLIENT_ID     | The client ID of the GitHub app to use for auth     |
| GF_AUTH_GITHUB_CLIENT_SECRET | The client secret of the GitHub app to use for auth |
| GF_SECURITY_ADMIN_PASSWORD   | The admin password of the Grafana admin console     |

## Provisioned dashboards

Dashboard providers and dashboard JSON are stored in
`dashboard-provisioning.yaml`. Grafana loads them into the `Dragonfly` folder and
polls the mounted files every 30 seconds.

Provisioned dashboards are read-only in the Grafana UI. Update their JSON in this
repository so Git remains the source of truth. Removing a provisioning file does
not delete its dashboard from Grafana, and the provider does not manage dashboards
outside the `Dragonfly` folder. The deployment mounts only the Dragonfly provider
file and dashboard subdirectory, leaving other file-based providers and dashboards
unmasked.
