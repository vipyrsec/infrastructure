# Staging OpenGrep alert viewer

The September 25, 2026 incident exhausted the Discord server's active-thread
capacity. Production and staging each occupied 500 active threads. Completed
OpenGrep results waited up to three hours for publication.

Bot PR [#345](https://github.com/vipyrsec/bot/pull/345) replaces automatic evidence
threads with an OpenGrep summary on the original alert and a persistent
**View findings** button. Findings open in private pages with independent
navigation and Inspector links. Mainframe remains the durable evidence store;
no database migration or API deployment is needed. `/lookup` uses the same
viewer. Existing threads are preserved.

Bot PR [#347](https://github.com/vipyrsec/bot/pull/347) folds the summary into an
OpenGrep field in the original verdict embed: pending becomes complete or partial
without adding a second block. Failed queue requests show an unconfirmed status
instead of promising a result. Older two-embed alerts remain compatible with the
persistent findings button.

## Release scope

Deploy to `do-sfo3-staging`, namespace `discord`, deployment `bot` only.
Production rollout follows the staging monitoring period. Bulk archiving of
both feeds follows successful production rollout; it is not part of this
staging deployment.

The bot image workflow builds and signs the release. Record its source commit,
digest, and successful workflow run before deployment. Set only the staging
container image, so environment secrets and unrelated workload configuration
remain intact.

Release commit: `2de149bd1cc3013f0355d8a99ba5440bceafba50`.
The [image workflow](https://github.com/vipyrsec/bot/actions/runs/36132879824)
successfully built, signed, and published digest
`sha256:256c4bcc289a9e3dc9d222fffb7af14a1945f33754d574d50c6211cbd06610c1`.

Confirm the context before setting the environment-specific image:

```bash
kubectl config get-contexts do-sfo3-staging
kubectl --context do-sfo3-staging -n discord set image deployment/bot \
  bot=ghcr.io/vipyrsec/bot:sha-2de149bd1cc3013f0355d8a99ba5440bceafba50@sha256:256c4bcc289a9e3dc9d222fffb7af14a1945f33754d574d50c6211cbd06610c1
kubectl --context do-sfo3-staging -n discord rollout status deployment/bot
```

## Verification

The first candidate (`eb0c9ea`) rolled out at 11:44 UTC but exposed an
extension-discovery regression. The bot treated the new viewer helper as an
extension without a `setup` entry point. Staging was restored to the prior image
and completed startup at 11:45:38 UTC. The helper was moved outside `bot.exts`,
and the smoke test now checks every extension discovered by the real loader.
The correction is in bot PR [#346](https://github.com/vipyrsec/bot/pull/346).
The corrected image completed startup at 11:51:20 UTC. The old publication leases
drained by 11:56 UTC. Fresh results published in 26 and 37 seconds, and a later
result published in 3 seconds. A read-only query before the final rollout found no unpublished
alerted results. No new threads were created for these results.

One duplicate staging alert (`1553009262698172480`) from the first candidate was
left pending when Mainframe rejected duplicate queueing. Its summary was repaired
from the stored completed result, preserving actions and suppressing mentions.
PR #347 handles this queue-failure state for subsequent alerts.

The final single-embed change passed 141 tests with warnings treated as errors,
the complete repository hook suite, strict Pyright, Ruff, and ty. Tests cover
preserved verdict and action state, private navigation, restart persistence,
legacy-message compatibility, queue failures, and publication retry safety.

The final image completed startup at 12:07:10 UTC with all extensions loaded.
Nine recent bot-authored staging alerts were consolidated from two embeds to one
by editing their embeds only; the script verified that action components were
unchanged. This included the
[104-finding example](https://discord.com/channels/1121450543462760448/1121471544355455058/1553011029250936866).
Production was verified to remain on `618f19e`; no threads were archived.

- Confirm the staging pod runs the expected image and logs a successful startup.
- Confirm completed OpenGrep results update their originating alerts, retain
  Report/Suppress actions, and expose View findings without creating threads.
- Check that unpublished results drain, failed edits remain retryable, and
  publication logs contain no thread-capacity errors.
- Check a newly arriving package progresses from pending to a completed summary.
- During human monitoring, open View findings, navigate several pages, and use
  Inspector links. Two investigators should have independent page positions.
- Verify the findings action remains registered after a bot restart.
- Confirm production still runs the previous image throughout staging monitoring.

## Rollback

The prior staging image is
`ghcr.io/vipyrsec/bot:sha-618f19e39b9fd6da469cf54b2b1da2f5c4a25c3b@sha256:f4fe759eda533218f4c8c815f8971494f8ca01aa4c506528f7f52490c0d5b2ce`.
Rollback requires only restoring that image on the staging deployment.
Stored evidence remains in Mainframe; the old publisher will again depend on
Discord thread capacity, and the new findings button requires the new bot code.
