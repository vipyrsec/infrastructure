# Staging durable scanner cache

This replaces cross-job process memory with optional PostgreSQL-backed results
for both scanners. Production is excluded. Within-package deduplication remains.
No package findings or existing scan tables are rewritten or backfilled.

## Identity and correctness

The durable identity is `(namespace, SHA-256(file bytes), language extension)`.
YARA uses an empty extension and reapplies rule filename filters to each path.
OpenGrep preserves its language extension and remaps findings to current paths.
Both clean and matched complete per-file results can be reused. Original file
contents are never uploaded or stored in the database.

A namespace includes scanner, rules repository commit, SHA-256 of the actual
rules corpus, and an engine fingerprint. The latter hashes the scanner executable
and, for OpenGrep, the actual engine executable, plus a cache-format version.
Rule names and contents use sorted, length-prefixed UTF-8 framing. SHA-256 is
computed alongside the existing XXH3 pass over input files, without a second
hashing read. Rules or executable changes produce misses, not stale reuse.
Mainframe also rejects a context that differs from its currently loaded rules.

The database is authoritative: database mode bypasses the process-local cache.
Each job prefetches bounded batches and retains only bounded response data.
Restarts discard this temporary data but the next worker can read persisted rows.
Every hundredth candidate is rescanned. YARA sorts rule sources before compilation
and canonicalizes results before comparison. An actual YARA finding mismatch
quarantines only the affected file hash/language, retaining evidence and quota
accounting until normal expiry. Lookups exclude quarantined entries; ordinary
writes cannot replace them. Failed quarantine requests remain blocked locally
and retry before subsequent job lookups. Local quarantine tracking is capped at
4,096 keys; reaching that limit disables only that process's reuse. Diagnostics
include file hash/path, result counts and at most 16 cached/fresh matches.

OpenGrep still requests generation revocation on a sampled mismatch. Server-side
generation revocation remains available for broader incidents. Jobs that already
consumed suspect cached output are rejected. Only the current authenticated worker
lease can publish results, quarantine files, or revoke a namespace.

OpenGrep retains its conservative rule eligibility and complete-coverage checks.
Failed, partial, unscanned and package-context-dependent inputs are not admitted.

## Database protection

- Dedicated pool: one connection per Mainframe process, no overflow, 50 ms pool
  timeout; cache work does not consume the canonical queue's connection pool.
- One concurrent cache operation and at most 10 API operations/second/process.
  Excess requests bypass caching. Staging Mainframe has one process/replica.
- At most 128 keys/results per request, 16 KiB/result, 512 KiB result bytes/write.
- Primary-key batch lookup; no per-file requests and no table-wide counts.
- Immutable rows with `ON CONFLICT DO NOTHING`; hits do not update timestamps,
  usage counters, TTLs, or result rows. Quota counters update once per write batch.
- Nonblocking per-scanner writer lock; 200 ms statement and 25 ms lock timeouts.
- Initial cap per scanner: 500,000 live rows and 64 MiB serialized result bytes,
  shared across at most eight rule/engine generations.
- Global physical-size admission threshold: 512 MiB, including indexes and TOAST.
  A batch already admitted can cross the threshold slightly; subsequent writes
  stop. This is an admission safeguard, not a PostgreSQL tablespace disk quota.
- Fixed 24-hour expiry, not extended on hits. Cleanup runs every minute and removes
  at most 1,000 expired rows per scanner/tick. It never cleans canonical findings.
  Table-specific autovacuum settings encourage reuse of space. Empty unrevoked or
  obsolete-rule namespaces are removed; active-rule
  revocation records remain.
- Workers stop cache requests for the job after a transport failure. Each request
  has a 750 ms timeout and new requests stop after two seconds of accumulated
  network time per job. Normal scanning continues when caching is unavailable.

Storage and latency metrics: `scanner_cache_storage_bytes`,
`scanner_cache_entries`, `scanner_cache_payload_bytes`,
`scanner_cache_request_seconds`, `scanner_cache_requests_total`,
`scanner_cache_rows_inserted_total`, `scanner_cache_rows_expired_total`, and
`scanner_cache_admission_skips_total`, and `scanner_cache_quarantined_total`. Existing accepted-result reuse metrics
continue to count actual avoided engine inputs; select a window after rollout to
separate this experiment from the previous in-memory cache. Worker `inserted_files`
is a local-cache metric; use server insertion metrics for durable admissions.

## Validation and initial sizing

The staging database was approximately 6.9 GB before rollout, including about
5 million canonical scan rows. No benchmark data was written to staging.

A disposable local PostgreSQL 16 benchmark loaded 500,000 clean cache entries
and 100,000 canonical scans. Cache table plus indexes occupied 120,299,520 bytes
(about 115 MiB). A 128-hit storage-layer lookup had median 4.56 ms, p95 5.18 ms.
The exact tuple-key/expiry SQL used primary-key bitmap scans and executed in
1.92 ms, with 2.23 ms planning time. Concurrent
unthrottled cache load changed canonical point-lookup p95 from 0.62 to 1.27 ms.
These are local warm-cache measurements, not staging latency guarantees or a
claim of zero database impact. Observe live request latency, quota skips, physical
size, queue health and database I/O before increasing admission budgets.

Socket vetted SHA-256 (`sha2` 0.10.9) and its newly resolved transitive dependencies.
The migration upgrades, downgrades and re-upgrades on disposable PostgreSQL;
a canonical scan sentinel survives downgrade unchanged.

## Staging settings and rollback

Mainframe: `SCAN_CACHE_ENABLED=true`. Defaults supply the budgets above;
`SCAN_CACHE_MAX_ENTRIES`, `SCAN_CACHE_MAX_BYTES`, `SCAN_CACHE_MAX_DISK_BYTES`, and
`SCAN_CACHE_TTL_SECONDS` allow explicit adjustment.

Both App Platform workers: `DRAGONFLY_REUSE_CACHE_DATABASE=true`,
`DRAGONFLY_REUSE_CACHE_MODE=reuse`, and `DRAGONFLY_THREADS=1`.

Deploy Mainframe first so startup applies Alembic revision `4d6a1c8f902b`.
Then deploy both scanners. Check durable reads/writes, queue responsiveness, and
reuse after a worker restart. Record immutable image digests and rollout time.

Immediate rollback: set `SCAN_CACHE_ENABLED=false` to make cache calls unavailable;
workers scan normally. Set worker `DRAGONFLY_REUSE_CACHE_MODE=off` to remove cache
requests altogether. Setting only `DRAGONFLY_REUSE_CACHE_DATABASE=false` restores
the old bounded process-local mode. No package rescan or data backfill is required.

Schema rollback, if desired after disabling callers: downgrade to `a71dc40e9b82`.
It drops only `scan_cache_entries` and `scan_cache_namespaces`. Stop the new image
from automatically upgrading the schema again before a deliberate downgrade.

## Rollout audit — 2026-09-16

Merged Mainframe #428, YARA #219, OpenGrep #11 and infrastructure #198 after
passing CI and Greptile review (5/5 on all three application PRs). Local tests:
296 Mainframe tests with 100% coverage, 47 YARA tests and 39 OpenGrep tests.
Full repository hooks passed. Review regressions cover malformed replies and
complete encoded HTTP write sizes, including JSON escaping.

Mainframe became ready on staging at approximately 23:15 UTC. Applied the staging
cache ConfigMap and added its optional env reference while preserving existing
configuration references. Updated only the mainframe container image. Startup
applied revision `4d6a1c8f902b`; both cache tables and the enabled flag were verified.
The cache initially occupied 24,576 bytes. The database reported seven connections
and zero deadlocks before worker activation.

- Mainframe commit: `50446982e68ec484de93484e073993177fb2d304`
- Mainframe image digest: `sha256:e1049b351d616949bd69ecaac4e2690b2e2c3f80e69a929ce37bc47170e1023a`
- YARA commit: `c49653df8285450062c475bd6c826450b92c8de5`
- YARA image digest: `sha256:99eb2999f429114ba8500005042029a130461d048d918fad74745dc702f84db5`
- OpenGrep commit: `d7d8d75389995013a019846528cd218619fda7e4`
- OpenGrep image digest: `sha256:90a0946ed6d813a87e67013ae9f8abe1fb513868002ca4b2920425904b5f7315`

Patched only `grafana-dashboard-rule-performance` on the observability cluster.
Verified all 23 existing panels were unchanged; the new row and six panels bring
the total to 30. New panels explicitly select staging. Prometheus scrapes the
new cache storage and per-scanner entry gauges.

App Platform deployment `5d4ac0a7-dcab-4a67-9492-3fe4151c2c6d` became active at
23:22:17 UTC in staging app `9d243898-5b30-4ab8-a432-df4b22bd356a`. Changed only
the two worker image digests and added `DRAGONFLY_REUSE_CACHE_DATABASE=true`.
Preserved sizes, instance counts, one-thread setting, reuse mode, and all other
App settings. No credentials were changed or committed.

By 23:24 UTC, YARA had persisted 2,589 file results (153,817 payload bytes;
851,968 physical bytes). Successful accepted results reported durable hits with
zero cache errors or mismatches. Early histogram p95 was approximately 24 ms for
lookups and 49 ms for writes; these small-sample server-operation observations
exclude network time and are not long-term performance conclusions.

Requested a staging-only YARA restart at 23:24:04 UTC to check persistence:
deployment `e74ee666-3cf7-4ab8-a257-0aafa8f554c1`.

The restarted YARA process reused two persisted entries while successfully
scanning `ocrmypdf 17.12.1` at 23:24:24 UTC, with zero cache errors or mismatches.
Its namespace fingerprint stayed unchanged and existing rows survived; subsequent
writes increased the total to 3,022 entries (974,848 physical bytes). Database
connections remained seven, with zero deadlocks. The observed dead-letter counter
did not increase during this initial rollout window.

OpenGrep was healthy and polling an empty eligible queue during initial validation.
Its database configuration is deployed, but no live durable hit was observed yet;
local integration tests cover persistence and restart behavior for both clients.

Production Mainframe's image and App Platform's active deployment, worker digests,
and instance counts exactly matched their pre-rollout snapshots. No production
resources or credentials were changed.

## YARA validation correction — 2026-09-17 UTC

YARA revoked its namespace at 00:10:54 UTC while scanning `aioli-cli 0.1.19`.
The cache rows were retained. Investigation compared 105 cached file paths from
that package with six fresh scans using the identical rule corpus. Finding order
varied, but no rule, score or filename-filter differences were found. Rule sources
were compiled from an unordered map and cached/fresh vectors were compared in
order. The worker had previously exited at 23:48:58 UTC while scanning
`griptape-nodes-editor-dist 0.126.0` (exit 128; OOM not established).

Mainframe #429 adds per-file quarantine and YARA #220 fixes deterministic
compilation, semantic comparison, isolation and diagnostics. No dependencies were
added. Validation: 300 Mainframe tests with 100% coverage, strict ty/Pyright,
51 YARA tests and complete hook suites. PostgreSQL migration
`6e2b9a140fd3` adds a default-false quarantine column with a two-second DDL lock
timeout. Upgrade/downgrade/re-upgrade preserves canonical data. On downgrade,
only generations containing quarantined rows are revoked before dropping the
column, preventing the older schema from reusing known-suspect entries.

The corrected YARA executable has a new engine fingerprint and warms a new
namespace. The old revoked generation is retained until normal expiry; it is
not re-enabled or copied across engine fingerprints. OpenGrep's image and
configuration are outside this recovery rollout.

Recovery image for Mainframe:
`ghcr.io/vipyrsec/dragonfly-mainframe:sha-85cf8a1a1de157e85d98070bd292beb3cadbef48@sha256:ab8bf919af3d336031da99fc6d9f365810ca4fd9107501ee1d01b9e78c5aa5a8`.
Applied only the staging mainframe container image; configuration references and
production resources were preserved.

YARA recovery commit: `d10aa6225e24a87d263a92f7ddcc6cc832315c7b`.
Both application PRs passed all CI and received Greptile 5/5. Review also verified
that quarantine acknowledgements are atomic (the counter reports newly changed
rows, not partial acceptance), and prompted a regression ensuring unrelated
pending cache writes survive quarantine.

Staging Mainframe readiness and revision `6e2b9a140fd3` were confirmed. The old
34,442-row YARA generation remained intact and revoked; OpenGrep's active cache
continued to grow. Database connections were six with zero deadlocks at that check.

YARA recovery image digest:
`sha256:f4bfb79068a632e076c5773e27417561cfddc9019bd636dff79e143ce9a22832`.
Changed only the staging App Platform `scanner` image digest; database caching,
reuse mode, one thread, worker resources and the OpenGrep worker were preserved.

Recovery App deployment `8f8cbf67-5ea4-4d49-a444-f5922a384916` became active at
00:56:08 UTC. Confirmed the active YARA digest and unchanged OpenGrep digest.
After that confirmation, requeued only the failed `aioli-cli 0.1.19` scan
(`3c5cbb60-3c97-4d79-9dd7-56ef495985a7`). A bounded, row-locked transaction verified
the exact cache-validation failure, attempt 1, and absence of dead-letter status
before changing FAILED to QUEUED and clearing the obsolete assignment and failure
reason. Preserved attempt count and existing package/rule data. This allows the
normal worker lease and result path to perform the retry.

The retry completed successfully at 00:57:07 UTC on attempt 2: score 60, three
matched rules, two durable cache hits, zero cache errors and zero mismatches.
Database status is FINISHED and the obsolete failure reason is cleared. The scan
completed in approximately 1.1 seconds. The new active YARA namespace is
`a99557ac623e0da2dafb54db4017af7d6bdf1d826d18b490e1830f0d289bbcf9`; initial
verification found 2,034 entries while the old revoked namespace remained intact.

Requested a staging-only YARA restart at 00:58:36 UTC. Deployment
`2888e3af-6fd0-4da3-9cbd-da984f796012` became active at 00:59:02 UTC. New worker
logs showed durable hits for `analog-sdk 0.20.0` (two files) and `ctrl-kd 4.9.0`
(three files), with zero mismatches. The active namespace fingerprint stayed the
same and persisted rows survived. One busy cache admission fell back to a fresh
scan; it did not revoke the namespace or prevent job completion.

Production Mainframe and scanner App deployment/digests/instance counts exactly
matched their pre-recovery snapshots. No production deployment was performed.

At 01:01:11 UTC after restart, `scc-firewall-manager-sdk 1.22.1514` reused 416 files
(5,385,421 bytes) and passed four sampled fresh comparisons with zero mismatches
or cache errors. This exercised the live validation path across process replacement.

Additionally requested temporary YARA `observe` mode at 01:02:40 UTC to compare
every cached candidate against fresh findings, preserving the same engine/rules
namespace. Temporary deployment: `d3d5fda7-3d2c-431b-a79c-0260660f3c6f`.

Observe mode completed seven fresh comparisons across four normal jobs at
01:03:54–01:03:56 UTC, with zero mismatches and zero cache errors. Restored the
exact pre-observe App spec (YARA mode `reuse`) after that validation. No other
worker settings or credentials were changed during the temporary check.

Final staging App deployment `3bf6f616-8742-4e75-bfd6-3ee05cfdd9ec` became active at
01:04:58 UTC. Verified YARA is back in `reuse` mode with the corrected image and
OpenGrep retains its existing image and reuse configuration.
