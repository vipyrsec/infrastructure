# Grafana

We use Grafana to display our metrics and logs from across our infrastructure.

Grafana stores its SQLite database and search indexes on a single-writer
persistent volume. The Deployment therefore uses the `Recreate` strategy so two
Grafana processes never access those files concurrently during a rollout.

The Grafana deployment expects a secret named `grafana-secret-env` with the following contents:

| Environment Variable         | Description                                         |
| ---------------------------- | --------------------------------------------------- |
| GF_AUTH_GITHUB_CLIENT_ID     | The client ID of the GitHub app to use for auth     |
| GF_AUTH_GITHUB_CLIENT_SECRET | The client secret of the GitHub app to use for auth |
| GF_SECURITY_ADMIN_PASSWORD   | The admin password of the Grafana admin console     |

Alerting expects a separate secret named `grafana-alerting-secret`:

- `GF_ALERTING_DISCORD_WEBHOOK_URL`: Discord webhook for Grafana alert
  notifications.

The webhook originates from a Discord server administrator, has no scheduled
expiration, and must be rotated in Discord if disclosed or abused. Create or
update the Kubernetes secret out of band; never commit the webhook URL.

## Provisioned alerts

`alerting-staging.yaml` provisions staging-only Dragonfly alert rules and a
staging-branded Discord contact point. Every rule filters on `cluster="staging"`
and includes an `environment=staging` label plus a `[STAGING]` summary.

The rules use the existing o11y Prometheus data source and alert on:

- dead-letter growth over the rolling seven-day average;
- failed-package growth over the rolling seven-day average;
- queue depth that is both abnormally high and rising;
- no package ingestion or successful scans during the preceding ten minutes.

The Prometheus deployment retains one week of data, so the rolling baseline uses
all available history. Alert rules route directly to the staging contact point
and do not replace the instance-wide notification policy.

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
