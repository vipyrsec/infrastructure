# Dragonfly queue observability

Mainframe reconciles its queue gauges from PostgreSQL once every 60 seconds by
default. Each replica performs one aggregate query per interval. Prometheus scrapes
and the environment's bot `/queue-status` invocations read the process-local
snapshot and do not issue database queries.

The aggregate is restricted to `QUEUED` and `PENDING` rows so PostgreSQL can use the
existing partial `scans.status` index. Keep `QUEUE_METRICS_REFRESH_SECONDS=60` in
staging and production unless a measured operational requirement justifies a
shorter interval.

## Grafana queries

Use these expressions in the existing Dragonfly staging-versus-production
dashboard. Retain the dashboard's `$cluster` selector.

Queue states over time:

```promql
max by (cluster, state) (
  packages_queue{cluster=~"$cluster", namespace="dragonfly", container="mainframe"}
)
```

Runnable backlog, excluding scans actively leased to a client:

```promql
sum by (cluster) (
  packages_queue{
    cluster=~"$cluster",
    namespace="dragonfly",
    container="mainframe",
    state=~"queued|retryable"
  }
)
```

The `stranded` state identifies invalid `PENDING` rows with no lease timestamp.
Workers cannot reclaim those rows, so they are visible as pressure but excluded
from runnable backlog.

Oldest runnable package age:

```promql
max by (cluster) (
  packages_queue_oldest_age_seconds{
    cluster=~"$cluster",
    namespace="dragonfly",
    container="mainframe"
  }
)
```

Snapshot staleness:

```promql
time() - max by (cluster) (
  packages_queue_snapshot_timestamp_seconds{
    cluster=~"$cluster",
    namespace="dragonfly",
    container="mainframe"
  }
)
```

Refresh failures:

```promql
sum by (cluster) (
  increase(packages_queue_refresh_failures_total{
    cluster=~"$cluster",
    namespace="dragonfly",
    container="mainframe"
  }[15m])
)
```

Compare these panels with the existing `packages_ingested_total`,
`packages_success_total`, and `packages_fail_total` rates to distinguish bursty
normal traffic from a stalled consumer.

## Staging flight

1. Deploy Mainframe to staging with the default 60-second refresh.
2. Confirm `packages_queue_snapshot_timestamp_seconds` advances once per minute.
3. Confirm snapshot staleness remains below 120 seconds and refresh failures remain
   zero.
4. Confirm the staging bot's existing `DRAGONFLY_API_URL` and Cloudflare Access
   service token target only staging.
5. Deploy the staging bot and verify `/queue-status` shows the staging queue only.
6. Observe database CPU, read IOPS, and query latency for at least one normal
   traffic window before promoting Mainframe to production.

If a refresh fails, Mainframe retains its last successful snapshot and increments
the failure counter. If a Mainframe pod is killed, Kubernetes recreates it according
to the Deployment; `/queue-status` is unavailable only until the replacement
process obtains its initial successful snapshot.

Repeat the same checks for the production bot after promotion. Production uses its
own `DRAGONFLY_API_URL` and Cloudflare Access service token and reports only the
production queue.
