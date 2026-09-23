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
The user subsequently authorized production durable caching as well. Startup applies additive
migrations; do not downgrade or drop retry records during image rollback.
Record image digest, deployment times and monitoring results below after rollout.

Live Alloy has pre-existing differences from the chart: HTTPS observability
destinations and extra PostgreSQL collectors. Apply only the `postgres_do`
block repair to the live ConfigMap, preserving those settings; do not apply the
whole rendered chart as part of this recovery.

## Validation and merged repairs

Mainframe [#431](https://github.com/vipyrsec/dragonfly-mainframe/pull/431) merged
as `a9ae11324d1e852d7ba225710bd0419c3aa59486`. All 348 tests pass with 100%
coverage and warnings treated as errors. PostgreSQL tests cover a deferred
COMMIT error, replacement of its connection, mixed successful/unavailable
packages, persistent retry recovery across sessions, duplicate submission,
missing packages, row-lock exclusion and bounded retry work. Migration upgrade,
downgrade and re-upgrade passed on a disposable local database. Complete hooks,
Ruff, strict Pyright and ty, and pedantic zizmor passed. CodeQL's metadata path
finding was fixed with input validation and traversal regression tests.

Infrastructure [#203](https://github.com/vipyrsec/infrastructure/pull/203) merged
as `6e32ba0061688f1bf21d2c160b930ac091334eca`. Complete hooks, pedantic zizmor,
strict Helm lint for both environments, and CI passed. Both merges used the
user-authorized admin bypass after validation. Greptile reported an expired trial;
the available code/security checks and manual review were completed.

Staging's `metrics_ca` and scoped Alloy ConfigMap patch were applied at 22:21:59
UTC. All three collectors subsequently reported successful HTTPS scrapes. Their
existing observability destinations and PostgreSQL collectors were preserved.
The provider CA and hostname were verified independently against both database
metrics endpoints before rollout.

The two upstream 503-triggering releases were already FINISHED in both databases:
`stac-fastapi.eodag 0.5.0` queued at approximately 09:24 UTC, and
`btrfs-timeline 0.3.0` at approximately 10:48 UTC on September 23. No manual
requeue was needed for those releases. This does not establish completeness of
every historical RSS batch.

## Staging gate caught a cleanup failure

The first signed image (`sha-a9ae11324d1e852d7ba225710bd0419c3aa59486`, digest
`sha256:8205c0f79f4611bd86edb0c5e89bc7ef8046ecb425792427c9ee289fd84974d4`)
became Ready at 22:36:55 UTC. Its release workflow initially stalled exporting
build cache; rerunning the workflow completed image signing and publication.
One loader job failed during the single-replica handover; subsequent jobs
succeeded. The existing zero-surge strategy waited for the old pod's memory
reservation to be released. No forced deletion or capacity changes were made.

Cache lookups and writes recovered, but cleanup repeatedly hit its 200 ms
statement deadline. Production promotion was held. The database contained
approximately 966,000 cache entries; a read-only EXPLAIN ANALYZE measured 345 ms
just to select 1,000 OpenGrep victims through the shared expiry index. The plan
scanned 17,190 entries, including other scanners' namespaces.

Mainframe follow-up [#432](https://github.com/vipyrsec/dragonfly-mainframe/pull/432)
adds a namespace/expiry index and bounds each scanner's cleanup to 100 rows per
tick using namespace-specific queries. It also propagates maintenance errors
through the cache transaction context to dispose the connection and release the
gate. All 352 tests passed with 100% coverage; the additive index migration
passed upgrade/downgrade/re-upgrade on disposable PostgreSQL 16.

The cleanup follow-up merged as `9e9056e7f269d8810aa0627cfef153e089083d28`.
All post-merge workflows, including image signing, passed. Staging became Ready
at 22:50:24 UTC on the resulting image:

```text
ghcr.io/vipyrsec/dragonfly-mainframe:sha-9e9056e7f269d8810aa0627cfef153e089083d28@sha256:1b6bdfb7b2fdfb0d2cd069309750bb508cd5c37c25eb28ce7f747226592bcf80
```

Migration `8b2d4e6f901a` and its index were verified live. The first maintenance
cycle expired 200 rows successfully. Read-only EXPLAIN ANALYZE of the new
100-row selection used the composite index in all six populated namespaces,
with measured execution times between 0.604 and 4.419 ms. The restarted
15-minute gate therefore ends no earlier than 23:05:24 UTC.

The second staging handover ran from 22:48:38 to 22:50:24 UTC. Loader attempts
at 22:49 and 22:50 failed while the single API replica was unavailable; regular
minute-by-minute ingestion resumed at 22:51. Archive-size rejections observed
during monitoring were normal scanner safeguards (oversized ZIP entries or
expanded tar archives), not API exceptions. A cache admission-busy response was
also observed under concurrent work; clients fall back to scanning normally.
This is distinct from the persistent database failures being repaired.

## Cache benefit since rollout

Prometheus counter increases from September 16 at 23:22:17 UTC through
September 23 at 23:03 UTC estimate 3.033 million reused YARA file inputs
(29.95% of lookups), representing 46.760 GB of engine input avoided. OpenGrep
reused approximately 183,203 inputs (11.84%), representing 3.416 GB. These are
estimated accepted-result telemetry totals, including scrape extrapolation;
they are not counts of unique files or measured end-to-end speedups.

For the period after the initial correctness correction and before the database
outage (September 17 at 01:05 through September 22 at 10:47 UTC), reuse rates were
39.79% for YARA and 15.81% for OpenGrep. Approximately 32,293 sampled fresh
comparisons reported no mismatches in that period. Full-window telemetry includes
one early YARA mismatch; the prior rollout audit describes its correction.

Across the full window, reported cache overhead averaged 241 ms per accepted
YARA result and 356 ms per OpenGrep result. These are accumulated wall-time
measurements, not CPU time saved. Live storage after the new index was about
338 MiB. Workload differences prevent a defensible percentage latency, CPU, or
infrastructure-cost improvement claim from these observations alone. Durable
caching remains staging-only; production benefits must not be inferred.

## Production cache promotion

While reviewing cache benefits, the user explicitly authorized enabling durable
caching in production. This supersedes the earlier staging-only restriction.
The staging gate passed at 23:05:29 UTC, after readiness at 22:50:24: 15 accepted
batches, 286 successful lookups, 169 writes, 3,000 expired rows, no cache database
errors, no restarts, and an empty retry backlog. One nonblocking admission-busy
fallback occurred; six logged package failures enforced archive-size limits.

The production ConfigMap now specifies the same tested limits: one million rows
and 64 MiB serialized payload per scanner, 512 MiB total physical admission
threshold, and 24-hour renewable TTL. The API deployment must add the optional
`dragonfly-mainframe-scan-cache` envFrom reference while preserving existing refs.
Deploy the fixed Mainframe image before enabling either worker.

Promote the exact staging worker image digests:

- YARA: `sha256:f4bfb79068a632e076c5773e27417561cfddc9019bd636dff79e143ce9a22832`.
- OpenGrep: `sha256:90a0946ed6d813a87e67013ae9f8abe1fb513868002ca4b2920425904b5f7315`.

For both workers, copy only the staging `DRAGONFLY_REUSE_CACHE_*` settings:
`MODE=reuse`, `DATABASE=true`, `ENTRIES=4096`, `BYTES=33554432`. Preserve production
credentials, URLs, instance sizes/counts, single-thread settings and all other
configuration. The DigitalOcean App spec is prepared from the current production
spec; complete specs remain outside the repository and are never printed.

Rollback can disable worker reuse (`DRAGONFLY_REUSE_CACHE_MODE=off`) and API
caching (`SCAN_CACHE_ENABLED=false`) without deleting cache or canonical data.
Prior worker digests: YARA `sha256:071b877e02d1344d96b1603027eb038fa5f2e203c60103ddd669ee8939baec02`;
OpenGrep `sha256:996a3e7239f39d383ed8ec5defc9e3b225c3ef03c9677ef55c1aeb2674c04a38`.

The rule-performance dashboard's reuse and durable-cache panels now honor the
existing cluster selector and retain cluster labels when both environments are
selected. Apply only that dashboard ConfigMap to observability. App-spec schema
validation passed; the create-oriented remote proposal endpoint cannot validate
an existing app's encrypted secret references. Production update preserves those
references unchanged and is validated by the update endpoint itself.
