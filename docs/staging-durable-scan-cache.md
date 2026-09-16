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
Every hundredth candidate is rescanned. A mismatch disables local reuse and
requests durable namespace revocation, so future lookups across workers cannot
use that generation. Revocation failures are explicitly logged. Jobs that consumed
suspect cached output are rejected. Only the current authenticated worker lease
can publish results or revoke a namespace.

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
  Table-specific autovacuum settings encourage reuse of space. Empty obsolete-rule
  namespaces are removed; active-rule revocation records remain.
- Workers stop cache requests for the job after a transport failure. Each request
  has a 750 ms timeout and new requests stop after two seconds of accumulated
  network time per job. Normal scanning continues when caching is unavailable.

Storage and latency metrics: `scanner_cache_storage_bytes`,
`scanner_cache_entries`, `scanner_cache_payload_bytes`,
`scanner_cache_request_seconds`, `scanner_cache_requests_total`,
`scanner_cache_rows_inserted_total`, `scanner_cache_rows_expired_total`, and
`scanner_cache_admission_skips_total`. Existing accepted-result reuse metrics
continue to count actual avoided engine inputs; select a window after rollout to
separate this experiment from the previous in-memory cache. Worker `inserted_files`
is a local-cache metric; use server insertion metrics for durable admissions.

## Validation and initial sizing

The staging database was approximately 6.9 GB before rollout, including about
5 million canonical scan rows. No benchmark data was written to staging.

A disposable local PostgreSQL 16 benchmark loaded 500,000 clean cache entries
and 100,000 canonical scans. Cache table plus indexes occupied 120,299,520 bytes
(about 115 MiB). A 128-hit storage-layer lookup had median 4.56 ms, p95 5.18 ms.
The sampled SQL used the primary-key index and executed in 0.41 ms. Concurrent
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
