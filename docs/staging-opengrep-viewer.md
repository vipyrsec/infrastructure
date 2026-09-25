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

## Release scope

Deploy to `do-sfo3-staging`, namespace `discord`, deployment `bot` only.
Production rollout follows the staging monitoring period. Bulk archiving of
both feeds follows successful production rollout; it is not part of this
staging deployment.

The bot image workflow builds and signs the release. Record its source commit,
digest, and successful workflow run before deployment. Set only the staging
container image, so environment secrets and unrelated workload configuration
remain intact.

Release commit: `cc8edd7dbe931563ce03266b0d7cd382425dfddf`.
The [image workflow](https://github.com/vipyrsec/bot/actions/runs/36131433069)
successfully built, signed, and published digest
`sha256:7ef0b53c3473853cd7ead48be7198dc76ad01da498bb487e20d58ed37aa44799`.

Confirm the context before setting the environment-specific image:

```bash
kubectl config get-contexts do-sfo3-staging
kubectl --context do-sfo3-staging -n discord set image deployment/bot \
  bot=ghcr.io/vipyrsec/bot:sha-cc8edd7dbe931563ce03266b0d7cd382425dfddf@sha256:7ef0b53c3473853cd7ead48be7198dc76ad01da498bb487e20d58ed37aa44799
kubectl --context do-sfo3-staging -n discord rollout status deployment/bot
```

## Verification

The first candidate (`eb0c9ea`) rolled out at 11:44 UTC but exposed an
extension-discovery regression. The bot treated the new viewer helper as an
extension without a `setup` entry point. Staging was restored to the prior image
and completed startup at 11:45:38 UTC. The helper was moved outside `bot.exts`,
and the smoke test now checks every extension discovered by the real loader.
The correction is in bot PR [#346](https://github.com/vipyrsec/bot/pull/346).
The corrected image must pass startup and publication checks before monitoring.

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
