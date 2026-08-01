# Dragonfly OpenGrep Shadow Rollout

## Purpose

Evaluate OpenGrep behavioral findings in staging without changing the existing
YARA scanner, its queue, its scores, or its production alert stream.

The shadow pipeline is enabled only for packages that produce a delivered,
unsuppressed YARA alert at or above the bot's configured score threshold.
Ordinary package ingestion does not create OpenGrep work.

## Isolation invariants

1. The YARA worker continues to use `/jobs`, `/rules`, and `/package`.
2. The OpenGrep worker uses only `/opengrep/jobs`, `/opengrep/rules`, and
   `/opengrep/package`.
3. After successfully delivering a qualifying YARA alert, the bot uses the
   authenticated `/opengrep/alerts` endpoint to make that package eligible for
   OpenGrep processing.
4. OpenGrep work and results are stored in an additive shadow table. They do
   not update the existing `scans`, `rules`, or `package_rules` tables.
5. OpenGrep endpoints are disabled by default. Mainframe refuses to start with
   the feature enabled unless `ENVIRONMENT=staging`.
6. The OpenGrep worker refuses to start unless its API origin is exactly the
   configured staging origin.
7. The shadow worker is a distinct DigitalOcean App Platform worker component
   with a distinct image repository. It is added only to the existing staging
   scanner App; no corresponding production component is introduced.
8. OpenGrep findings have no production score. The bot publishes them as
   staging evaluation evidence without an alert-role mention.

## Staging resource inventory

- App: `dragonfly-scanner-staging`
- Existing YARA component: `scanner` (unchanged)
- New component: `opengrep-shadow`
- Component kind: worker
- Component size: `apps-s-1vcpu-1gb` (1 shared vCPU, 1 GiB RAM)
- Component count: 1
- Image:
  `ghcr.io/vipyrsec/dragonfly-client-rs-opengrep-shadow@sha256:c39e869700924c89bb7090b77ae58253f9bcb44081846ffb452554b4edbe0c4b`
- Source tag: `sha-7ec7f4a7ea3822a269f04b5eb157b41e181b5f2b`
- Cloudflare Access application: `Mainframe`
- Access domain: `dragonfly-staging.vipyrsec.com`

The worker has the following non-secret configuration:

```text
DRAGONFLY_BASE_URL=https://dragonfly-staging.vipyrsec.com
DRAGONFLY_THREADS=1
DRAGONFLY_BULK_SIZE=1
```

Staging Mainframe receives
`OPENGREP_SHADOW_API_ORIGIN=https://dragonfly-staging.vipyrsec.com` from the
staging-only ConfigMap. Its startup guard requires this exact origin while
shadow mode is enabled. Cloudflare's Access audience remains environment
provided through `CF_ACCESS_AUDIENCE`; its value is not embedded in
application source.

`DRAGONFLY_CF_ACCESS_CLIENT_ID` and
`DRAGONFLY_CF_ACCESS_CLIENT_SECRET` are encrypted App Platform environment
variables. Create a dedicated one-year Access service token and add only its
token ID to the existing staging workload policy. Never place either
credential value in this repository, a pull request, a shell history, a
Kubernetes object, or deployment logs. Any temporary App spec containing the
one-time client secret must be mode `0600`, live outside the repository, and
be deleted immediately after App Platform accepts the update.

## Deployment order

1. Merge the OpenGrep corpus and service changes after required reviews pass.
2. Publish and verify the signed staging-only OpenGrep image.
3. Deploy the additive Mainframe database migration and updated image.
4. Apply the staging-only ConfigMaps and restart Mainframe and the bot.
5. Verify the existing YARA `/jobs` and `/package` flow.
6. Provision a dedicated staging Access service token through the provider
   control plane and add it to the existing staging workload policy.
7. Add one `opengrep-shadow` worker to the existing staging scanner App,
   preserving the `scanner` component byte-for-byte.
8. Confirm that ordinary package ingestion creates no OpenGrep work, then use
   a reviewed staging package that produces a qualifying YARA alert.
9. Compare YARA duration and findings with OpenGrep duration and findings.
10. Observe Mainframe, bot, and both App Platform worker logs for a continuous
    five-minute period with no unanticipated errors.

Only packages whose qualifying YARA alerts are delivered after the feature is
enabled receive shadow work. The rollout does not backfill historical
packages. Pre-gate shadow rows remain inert; if their package later produces a
qualifying alert, Mainframe reinitializes that single row for a fresh scan.

## Discord delivery

The bot replies inside the originating package-alert thread for each completed
OpenGrep scan. Equivalent findings are grouped by rule with consolidated
locations, and every reply remains within Discord's message limit. Thread
creation and replies are retried through the bot's existing polling loop;
Mainframe can replace a deleted checkpointed thread and records delivery only
after the complete replacement thread is published.

## Rollback

Rollback does not require dropping the additive table:

1. Remove the `opengrep-shadow` component from
   `dragonfly-scanner-staging`; do not change the existing `scanner`
   component.
2. Set `OPENGREP_SHADOW_ENABLED=false` on staging Mainframe and restart it.
3. Set `DRAGONFLY_OPENGREP_SHADOW_ENABLED=false` on the staging bot and restart
   it.
4. Remove the shadow token from the staging Access policy and revoke it.
5. Confirm the existing YARA client, queue status, and alert loop remain
   healthy.

Completed shadow rows remain available for offline evaluation. Queued or
pending shadow rows are inert while the feature is disabled and may be resumed
after re-enabling it.

## Controlled performance comparison

After shadow efficacy is established, the existing `scanner` and new
`opengrep-shadow` App Platform components can be scaled independently for a
bounded staging experiment. Pausing the YARA component does not redirect YARA
jobs to OpenGrep, and pausing OpenGrep does not redirect shadow jobs to YARA.
Record instance counts, component sizes, package cohort, wall-clock duration,
and result counts for every comparison window.

## 2026-08-01 performance rollout record

The partial-result, package-wide file-reuse, and Inspector-link changes were
deployed to staging after every pull request check passed. Greptile assigned
the worker, Mainframe, and bot changes confidence scores of 5/5 with no
remaining issues. The OpenGrep rule validation change deployed automatically
through security-intelligence workflow run `30684318724`.

The deployment changed only these immutable workload references:

- Mainframe previous:
  `ghcr.io/vipyrsec/dragonfly-mainframe:sha-46e5bf72be98a8c7d69944b17eb78b026b3860ac`
  at digest
  `sha256:5c8409796b7c1291575dcdf22ba3c3751dbd5dbdb4af321536e0f7d25805dfc5`.
- Mainframe deployed:
  `ghcr.io/vipyrsec/dragonfly-mainframe:sha-cde9d3e7217f9ad7b95033279101c7a4f56e5b80`
  at digest
  `sha256:d6f10438d4e039d8f77553a6b4f8992562e19356e47dbce8f57ea4006e97f88e`.
- Bot previous:
  `ghcr.io/vipyrsec/bot:sha-869821537d8f19d2265a97e3bcc04babec580f03`
  at digest
  `sha256:e8165bf64c8d3fa3aab531deff8d39f2b9d85a97cef64489d660fc1eb5a95917`.
- Bot deployed:
  `ghcr.io/vipyrsec/bot:sha-a33ea65e51861de395cb445b1f5e04f01c0e1cf9`
  at digest
  `sha256:84d65f3c791e74e7a3492f547cfa0757acd45f43cc1b4e8180fdcf15c6a91a71`.
- OpenGrep shadow previous:
  `ghcr.io/vipyrsec/dragonfly-client-rs-opengrep-shadow`
  at digest
  `sha256:475e447d0432ed143b74b0175f96cc25dfbca80a13abb34633672251517b9a24`.
- OpenGrep shadow deployed:
  `ghcr.io/vipyrsec/dragonfly-client-rs-opengrep-shadow`
  at digest
  `sha256:c39e869700924c89bb7090b77ae58253f9bcb44081846ffb452554b4edbe0c4b`.

Kubernetes context `do-sfo3-staging` reported successful Mainframe and bot
rollouts with one of one replicas ready. DigitalOcean App
`9d243898-5b30-4ab8-a432-df4b22bd356a` activated deployment
`c5be1503-d049-441d-9917-c80ea3b9308b`; the existing `scanner` worker remained
at digest
`sha256:62a7b64d7a0d0967fe2dc581ce8b061169aeb5a27f99c4f7f730403b5b90a028`.

The first observed post-deployment OpenGrep job reused findings for 38 files
across two distributions and completed in 10.734 seconds with zero findings
and `partial=false`. Mainframe accepted the result and publication lifecycle
requests with HTTP 200 responses. The bot loaded its Dragonfly extension and
sent its startup notification successfully.

To roll back this performance revision without changing schema or secrets,
restore the previous immutable reference for each affected component from the
table above. Wait for both Kubernetes rollouts and the App Platform deployment
to become healthy before evaluating the rollback. The nullable Mainframe
field reused for partial diagnostics requires no reverse database migration;
older workers omit the new response field safely.
