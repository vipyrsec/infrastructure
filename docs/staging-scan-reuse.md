# Staging cross-package scan reuse experiment

## Scope and rollback

Only DigitalOcean App `dragonfly-scanner-staging`
(`9d243898-5b30-4ab8-a432-df4b22bd356a`) receives this experiment, in its
`scanner` and `opengrep-shadow` worker components. Production is excluded.
The existing Kubernetes client Deployment is scaled to zero and is not the
active scanner. No Helm chart, database schema, queue, or result API changes.

Each process retains at most 4096 entries and 32 MiB of content plus encoded
results, with FIFO eviction. Entry/index overhead is additionally bounded by
the entry limit. Restarts and successful rules reloads clear the cache. This
first experiment does not share results between replicas or survive restarts.
That trades some possible hits for isolation and zero per-file database traffic.
Rules and engine lifetime scope the cache; original bytes must compare equal,
and OpenGrep language extensions are part of its keys. Failed/incomplete
OpenGrep runs and path-scoped rules do not populate the cross-package cache.

Set these non-secret, RUN_TIME worker environment variables:

```text
DRAGONFLY_REUSE_CACHE_MODE=reuse
DRAGONFLY_REUSE_CACHE_ENTRIES=4096
DRAGONFLY_REUSE_CACHE_BYTES=33554432
```

The full staging rollout uses `reuse` to skip candidates, with every hundredth
hit rescanned. `observe` remains available for a controlled rescan baseline.
A result mismatch disables reuse in that process and emits an error. Record
both deployment IDs, image digests, observation windows and workload mix.
OpenGrep is alert-gated, so idle periods do not establish a performance result.

Rollback: set `DRAGONFLY_REUSE_CACHE_MODE=off` on both staging workers and
redeploy, or restore their previous immutable image digests. No migration,
backfill, data deletion or database downgrade is necessary. Existing package
findings remain stored and continue to be returned normally.

## Multi-day Grafana measurement

The **Dragonfly rule performance** dashboard has a **Staging scanner reuse
experiment** section. Its queries explicitly select `cluster="staging"`.
Select a 3-day or 7-day range to see skipped inputs/bytes, sampled rescans,
mismatches, measured engine time, cache overhead, report counts and cache errors.
Timeseries show avoided input percentage, average engine time per reported job,
eviction rate and the age of the last report.

Workers attach bounded telemetry to their existing result submissions.
Mainframe increments fixed-cardinality counters after the accepted lease's
transaction commits. Replays and rejected leases are not counted. Prometheus
scrapes and stores these time series; there are no extra database reads/writes,
per-file requests, migrations or rules/package labels in the metric series.
Mainframe restarts reset process counters; `rate`/`increase` account for resets,
although reports between the last scrape and a crash can be lost. Work whose
result is never accepted is excluded from these durable counters and remains
visible in worker logs. OpenGrep path-scoped fallback reports have no reusable
file counts. Do not equate a missing/idle report with verified zero work.

## Log-window measurement

Both workers emit `event="scan_reuse"` per package job, including jobs that fail.
The job span carries the rules commit and package version. Aggregate a bounded,
non-overlapping App Platform log window using the report script:

```bash
doctl apps logs 9d243898-5b30-4ab8-a432-df4b22bd356a scanner --tail 1000 \
  | uv run --no-project python scripts/scan-reuse-report.py
doctl apps logs 9d243898-5b30-4ab8-a432-df4b22bd356a opengrep-shadow --tail 1000 \
  | uv run --no-project python scripts/scan-reuse-report.py
```

Confirm the DigitalOcean context is `vipyr` first. The script prints totals
separately for scanner, mode and rules commit. Do not add overlapping snapshots.
Log retention limits the measurement window; absence of records is not zero work.

- **Candidate files** are hits even when observation or audit still scans them.
- **Reused files/bytes** are engine inputs actually skipped beyond the existing
  within-package deduplication. Downloads and extraction still happen.
- **Engine files/bytes** are submitted unique targets, including targets the
  engine may subsequently ignore. They exclude extra fallback retry attempts.
- **Engine wall time** is measured elapsed engine execution, not CPU time.
- **Cache overhead** measures lookup, byte verification and insertion wall time,
  including lock waits. Existing file hashing is not a new cache cost.
- **Validated/mismatched files**, cache errors and evictions indicate correctness
  and capacity pressure. Investigate any mismatch before further reuse.

Compare observe/reuse windows on similar packages under the same rules, engine,
worker size and instance count. Reused input counts are directly measured;
reductions in billed CPU, elapsed package latency or money require a comparable
workload and separate resource/cost measurements. Do not infer them from hit rate.

## Pre-experiment images

- YARA: `sha256:071b877e02d1344d96b1603027eb038fa5f2e203c60103ddd669ee8939baec02`
- OpenGrep: `sha256:996a3e7239f39d383ed8ec5defc9e3b225c3ef03c9677ef55c1aeb2674c04a38`
