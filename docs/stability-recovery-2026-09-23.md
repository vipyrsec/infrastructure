# Stability recovery — 2026-09-23

The user authorized repairs, admin merge bypass, and production rollout only
after staging deployment and monitoring.

## Findings and repairs

- PyPI metadata errors caused 17 production and 19 staging ingestion failures
  in the 24 hours ending September 23 at 21:57 UTC. Mainframe now retries
  transient failures, limits metadata concurrency, commits unrelated packages,
  and retains unresolved packages in `ingestion_retries` for bounded background
  retry. The new migration creates only this retry table and its due-time index.
- Staging cache COMMIT timed out on September 22 at 10:47:42 UTC. Its pooled
  connection then repeatedly failed with `InFailedSqlTransaction`, including
  all approximately 9,138 lookups during the investigation window. Mainframe
  now discards the isolated cache pool after database errors.
- Both Alloy managed PostgreSQL scrapers used HTTP against a TLS endpoint,
  returning EOF. The chart now uses HTTPS and the provider's CA, preserving
  certificate-chain and hostname verification.

## Monitoring prerequisite

Before applying the Alloy change, add `metrics_ca` to the existing
`postgres/dragonfly` Secret in the target cluster. Preserve all existing keys.
Its value is the PEM-decoded public certificate returned by
`doctl databases get-ca <cluster-id> -o json`. No credentials are rotated.

The staging cluster ID is `6c6d9dfc-1ef2-4f81-a45a-97964b6a8904`; production is
`5ddebe03-f96b-4445-96fb-34d9fa29914b`. Both currently return the same project CA,
valid June 8, 2023 through June 5, 2033, with SHA-256 fingerprint
`14:DC:72:CB:69:75:2D:E0:42:A5:FF:C4:3D:10:E9:76:29:89:6C:4A:F1:ED:16:EE:C8:A8:67:DE:47:BD:9E:37`.
Refresh the value if the provider rotates the CA. The certificate is public;
the existing Secret is used to keep the database monitoring inputs together.

References: [DigitalOcean metrics endpoint](https://docs.digitalocean.com/products/databases/postgresql/how-to/monitor-databases/)
and [Alloy TLS configuration](https://grafana.com/docs/grafana-cloud/observe-and-act/send-data/alloy/reference/components/prometheus/prometheus.scrape/).

## Rollout gates

Deploy the immutable Mainframe image and telemetry change to staging first.
Observe at least 15 minutes of live ingestion, cache requests and maintenance,
with no persistent cache transaction failures, healthy API readiness, successful
loader jobs, and managed database `up=1`. Confirm retry backlog drains if any
upstream failures occur. Local regressions exercise the retry path under failure
even if PyPI remains healthy during the live observation period.

Only then promote the same image and monitoring configuration to production.
Preserve production's disabled durable-cache setting. Startup applies additive
migrations; do not downgrade or drop retry records during image rollback.
Record image digest, deployment times and monitoring results below after rollout.

Live Alloy has pre-existing differences from the chart: HTTPS observability
destinations and extra PostgreSQL collectors. Apply only the `postgres_do`
block repair to the live ConfigMap, preserving those settings; do not apply the
whole rendered chart as part of this recovery.
