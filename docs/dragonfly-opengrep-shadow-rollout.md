# Dragonfly OpenGrep Shadow Rollout

## Purpose

Evaluate OpenGrep behavioral findings in staging without changing the existing
YARA scanner, its queue, its scores, or its production alert stream.

## Isolation invariants

1. The YARA worker continues to use `/jobs`, `/rules`, and `/package`.
2. The OpenGrep worker uses only `/opengrep/jobs`, `/opengrep/rules`, and
   `/opengrep/package`.
3. OpenGrep work and results are stored in an additive shadow table. They do
   not update the existing `scans`, `rules`, or `package_rules` tables.
4. OpenGrep endpoints are disabled by default. Mainframe refuses to start with
   the feature enabled unless `ENVIRONMENT=staging`.
5. The OpenGrep worker refuses to start unless its API origin is exactly the
   configured staging origin.
6. The shadow worker is a distinct DigitalOcean App Platform worker component
   with a distinct image repository. It is added only to the existing staging
   scanner App; no corresponding production component is introduced.
7. OpenGrep findings have no production score. The bot publishes them as
   staging evaluation evidence without an alert-role mention.

## Staging resource inventory

- DigitalOcean context: `vipyr`
- App: `dragonfly-scanner-staging`
- App ID: `9d243898-5b30-4ab8-a432-df4b22bd356a`
- Existing YARA component: `scanner` (unchanged)
- New component: `opengrep-shadow`
- Component kind: worker
- Component size: `apps-s-1vcpu-1gb` (1 shared vCPU, 1 GiB RAM)
- Component count: 1
- Image: `ghcr.io/vipyrsec/dragonfly-client-rs-opengrep-shadow` pinned
  by immutable digest
- Cloudflare Access application: `Mainframe`
- Access application ID: `a252d918-8780-40d3-b44c-a66ef899d5d6`
- Access domain: `dragonfly-staging.vipyrsec.com`
- Access service token: `dragonfly-opengrep-shadow-staging`

The worker has the following non-secret configuration:

```text
DRAGONFLY_BASE_URL=https://dragonfly-staging.vipyrsec.com
DRAGONFLY_THREADS=1
DRAGONFLY_BULK_SIZE=1
```

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
6. Create the dedicated staging Access service token and add it to the
   existing staging workload policy.
7. Add one `opengrep-shadow` worker to the existing staging scanner App,
   preserving the `scanner` component byte-for-byte.
8. Queue synthetic, known-benign, and reviewed test packages.
9. Compare YARA duration and findings with OpenGrep duration and findings.
10. Observe Mainframe, bot, and both App Platform worker logs for a continuous
    five-minute period with no unanticipated errors.

Only packages queued after the feature is enabled receive shadow work. The
rollout does not backfill historical packages.

## Discord delivery

The bot sends one bounded summary message per completed OpenGrep scan. When
findings exist, it creates a thread from that message and sends bounded chunks
of finding evidence. Each chunk remains within Discord's message limit. The
summary and thread creation are retried through the bot's existing polling
loop; Mainframe records delivery only after the complete thread is published.

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
