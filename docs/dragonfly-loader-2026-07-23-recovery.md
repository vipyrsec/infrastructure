# Dragonfly loader production recovery — 2026-07-23

## Impact

Production package ingestion stopped after the loader Job scheduled at
2026-07-22 07:33 EDT became stuck. Previously queued scans continued until
approximately 09:13 EDT.

## Root cause

The affected worker's 197 MiB `/run` tmpfs filled during Cilium CNI log
rotation. Cilium's active log was approximately 95 MiB, its uncompressed
archive was 100 MiB, and the failed compression left a temporary archive.
Almost all Cilium warnings were generated while deleting the short-lived,
per-minute loader pods.

The full tmpfs prevented `runc` from writing container state, leaving the
loader pod in `ContainerCreating`. The CronJob's `Forbid` concurrency policy
then prevented every subsequent schedule from starting.

Staging also exposed an independent application issue: its older mainframe
image rejected PyPI's `core-metadata` JSON field. Mainframe image
`sha-2e12201604066ccb1780aaddc16dfc4face6654d` contains the regression-tested
PyPI JSON compatibility fix.

## Production maintenance

The following actions were completed on 2026-07-23:

1. Upgraded the production DOKS cluster from `1.34.1-do.1` to
   `1.34.8-do.3` using surge upgrades.
2. Confirmed DigitalOcean replaced both workers. Replacing the affected
   worker cleared the node-local `/run` exhaustion.
3. Confirmed the previously stuck Job completed after being recreated on an
   upgraded worker.
4. Applied the merged CronJob controls:
   - `startingDeadlineSeconds: 120`
   - `activeDeadlineSeconds: 120`
   - `backoffLimit: 0`

The production loader image was intentionally left at
`11f0384fa8d5c07a6e4e7546a7566d69c5f6d02a`. Changing loader authentication
and recovering scheduling were kept as separate maintenance concerns.

## Validation

- Both production workers are Ready on Kubernetes `v1.34.8`.
- The first Job created from the hardened template completed successfully.
- Loader requests to `POST /batch/package` returned HTTP 200.
- The scanner began processing newly queued packages.
- Scanner result submissions to `PUT /package` returned HTTP 200.
- The new workers' `/run` tmpfs filesystems were 2–3% used.
- All production deployments returned to their desired replica count.

## Deferred image reconciliation

Loader image selection remains intentionally deferred:

- production: `11f0384fa8d5c07a6e4e7546a7566d69c5f6d02a`
- staging: `sha-9f67b5bfcab22089deef147902532c3c9f17d90b`
- current manifest: `sha-fc9128434c0f15b90e7f0ec686bd1932f3c5fd4a`
- latest successful main image build:
  `sha-74257a59ab7051d3c5d4cf3f08df020d599a9882`

The newer loader line changes authentication from the legacy provider to
Cloudflare Access. Reconcile the target image and production credentials as a
separate, explicitly reviewed change.
