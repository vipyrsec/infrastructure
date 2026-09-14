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

`alerting-staging.yaml` and `alerting-prod.yaml` provision independent Dragonfly
rule groups and environment-branded Discord contact points. Every rule filters
on its exact `cluster` label and includes a matching `environment` label.
Discord titles and individual alert bodies identify the environment.

The rules use the existing o11y Prometheus data source and alert on:

- dead-letter growth over the rolling seven-day average;
- failed-package growth over the rolling seven-day average;
- queue depth that is both abnormally high and rising;
- no package ingestion or successful scans during the preceding ten minutes.
- low node memory headroom or sustained memory stalls;
- fewer than three healthy node or container telemetry targets in either environment.

The node telemetry rules assume three workers per cluster. Update the expected
counts when resizing a pool. See `docs/node-resource-recovery.md` for resource
budgets, collection changes, validation, and the staged rollout procedure.

The Prometheus deployment retains one week of data, so the rolling baseline uses
all available history. Alert rules route directly to their environment contact point
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

## Discord notifications

Contact points format firing and resolved alerts separately, including mixed
notification groups. Each alert includes its environment, service, severity,
affected node when available, human-readable measurements, UTC timestamps, and
an alert link. Firing alerts also include the sustained threshold and a first
investigation step. Silencing remains available from the alert page. Measurements
describe the last rule evaluation; package increases can be fractional because Prometheus extrapolates
counter samples. A cleared baseline alert means its combined trigger cleared,
not necessarily that failures or queue depth returned to zero.

Recovery summaries replace stale firing headlines. A Grafana state reason (for
example, missing series or a paused rule) takes precedence over recovery wording
and asks operators to verify the alert. Evaluation errors retain their diagnostic
message, capped at 400 characters. The default expression and label dump is
omitted. Messages stay below Discord’s 2,000-character limit; oversized groups include an explicit omission notice and
a link to the complete alert list.

Contact-point message variables use `$$` in provisioning files because Grafana
expands environment variables in receiver settings. Grafana stores a single `$`
in the resulting Go template. Preview the stored template after provisioning as
well as the unescaped source; the preview API alone does not perform provisioning
substitution. Rule annotations use ordinary `$values` and `$labels`.

Update both environment files together. Rule annotations hold the descriptions,
threshold explanations, recovery summaries, and investigation steps. The expected
worker count in descriptions must stay aligned with the telemetry expressions.
Preview message templates with Grafana's template test API (which sends no
notifications), including firing, resolved, mixed, and missing-data cases.

Apply both ConfigMaps and restart the Grafana Deployment to refresh its subPath
mounts and reload provisioning. This causes a brief Grafana interruption because
its SQLite volume requires the Recreate strategy. Verify both contact points and
all 16 rules after the rollout; Prometheus collection continues independently.
