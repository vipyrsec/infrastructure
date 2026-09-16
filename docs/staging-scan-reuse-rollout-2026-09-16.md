# Staging scan reuse rollout — 2026-09-16 UTC

Explicit user authorization: merge Mainframe #427, YARA #218, OpenGrep #10,
infrastructure #196 using admin bypass if required; deploy staging only.

Mainframe #427 merged as 65631f317fdd210e7f52bc2e5e47dd158a8b0e47.
Infrastructure #196 merged as 37cc9fd506cb589f8352cafe751929dc94577509.

Staging Mainframe deployed image:
`ghcr.io/vipyrsec/dragonfly-mainframe:sha-65631f317fdd210e7f52bc2e5e47dd158a8b0e47@sha256:51dad6235456ace5a4d6c880707b19d34a68f41ffb59f0c778c6922a1fc84057`

Previous staging Mainframe image:
`ghcr.io/vipyrsec/dragonfly-mainframe:sha-d84b4e0197b8fc9436555bab59a89d779b1f881e@sha256:5d43face16a7df4004e7339b1aa93b6bc6ce23dfe3d4a0090f267cdb72dda9ed`

Both scanner modes: reuse, 4096 entries, 33554432 retained bytes, one thread.
No database migrations. No production deployment or configuration changes.
Mismatches disable reuse and reject jobs that consumed cached output; fully
fresh observation results are preserved.

YARA #218 merged as 0388f9418372dad4c73eab2ea18a5329e15577e2.
OpenGrep #10 merged as a8ec2345bca0f162b51dd902de36f2aec6369eb1.
All PR CI checks passed; Mainframe, YARA and OpenGrep Greptile reviews scored 5/5.
Infrastructure has no Greptile check. Both scanner image publication/signing
workflows completed successfully.

Staging App deployment: ac427040-d843-4adb-9307-3c3e638aa544.
Previous deployment: d53fff8a-f0e4-47bf-b79c-2780ce7fdfc2.

- YARA image: `sha256:e9e256a7618ccf1e3be62aec2c60614bd024d69567428a5f67395145db792905`
- OpenGrep image: `sha256:0465bab3d9908c1f6f352c7214e2da44a51de4266bc13ae0203d581a91b98779`

The existing one-replica worker sizes are preserved: YARA apps-s-1vcpu-0.5gb,
OpenGrep apps-s-1vcpu-1gb. Existing credential values are preserved unchanged;
no credentials were added or rotated.

The shared observability cluster received only the rule-performance dashboard
ConfigMap update. Its 10 existing panels are unchanged; 13 staging experiment
panels/row were added. All 12 new PromQL expressions executed successfully.
Grafana loaded the projected dashboard file without a restart.

The user explicitly accepted process-local cache loss on scanner restarts for
this initial experiment. Interpret reuse alongside worker restart frequency.

Deployment became ACTIVE at 2026-09-16T03:09:08Z, all 9 rollout steps succeeded.
At 03:09 UTC, the first YARA package report was accepted and scraped by
Prometheus: 1649 fresh inputs, 1649 cache inserts, zero cross-job hits (cold
start), zero cache errors and zero mismatches. The pre-existing within-package
676 reused files are deliberately excluded from the new cross-job savings.
OpenGrep started successfully and initially reported no available shadow jobs;
its zero reports at that point do not establish end-to-end result validation.

At 03:11 UTC, Prometheus had accepted 9 YARA reports and 1 OpenGrep report.
YARA recorded 2032 lookups, 14 cross-job skips (1725 bytes), 2018 engine inputs,
and 2011 evictions. Both scanners had zero cache errors or mismatches; no audit
sample had yet occurred. These cold-start counts are not an improvement claim.
The eviction count makes the 32 MiB budget an important part of the evaluation.

OpenGrep's first package (`psi-agent` 0.0.1a20260916) failed because the engine
reported syntax errors. This follows the pre-existing scan-error classification;
the worker remained running, its failure telemetry was accepted, and no results
from that failed scan entered the cache. Successful OpenGrep reuse still needs
eligible workload during the observation period.

Production verification: the App deployment remains
`01cc4cbc-2927-4c7a-a2b4-b5876073463d`; its worker image/count snapshot is identical
before and after rollout. Production Mainframe remains on the pre-experiment
`d84b4e0` image listed above.
