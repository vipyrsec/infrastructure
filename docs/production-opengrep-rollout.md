# Production OpenGrep rollout and feed thread archive

On September 25, 2026, production was promoted to the same signed bot image
validated on staging. The user explicitly authorized production promotion and
bulk archiving of active threads in both feeds after staging monitoring.

## Release

Source: [bot PR #347](https://github.com/vipyrsec/bot/pull/347), commit
`2de149bd1cc3013f0355d8a99ba5440bceafba50`.
Signed build: [36132879824](https://github.com/vipyrsec/bot/actions/runs/36132879824).
Image digest:
`sha256:256c4bcc289a9e3dc9d222fffb7af14a1945f33754d574d50c6211cbd06610c1`.

Staging published fresh results for `ccherd@0.3.0` and
`bitranox-skills@7.23.6` using the single-embed publisher before promotion.
The DigitalOcean context was confirmed as `vipyr`, and Kubernetes contexts were
confirmed before using explicit staging and production context arguments.

The production deployment image was updated using:

```bash
kubectl --context do-sfo3-prod -n discord set image deployment/bot \
  bot=ghcr.io/vipyrsec/bot:sha-2de149bd1cc3013f0355d8a99ba5440bceafba50@sha256:256c4bcc289a9e3dc9d222fffb7af14a1945f33754d574d50c6211cbd06610c1
kubectl --context do-sfo3-prod -n discord rollout status deployment/bot
```

Production completed startup with all extensions loaded at 12:16:05 UTC.
The new pod was ready with zero restarts. `crow-cli@0.1.45` published at
12:17:07 UTC, 50 seconds after scan completion, with no thread ID. Its
[original alert](https://discord.com/channels/1121450543462760448/1121462652342910986/1553016998768676917)
was updated by the new publisher.
Shared manifests and Helm charts were unchanged. No credentials were changed
or included in this record. See the [staging record](staging-opengrep-viewer.md)
for implementation validation and the prior startup regression correction.

## Thread archiving

After successful production startup, each environment's bot authenticated with
its existing runtime credentials. The archive script checked the guild and feed
IDs, enumerated active threads, and edited only threads whose parent matched
that environment's feed:

- Guild: `1121450543462760448`.
- Production feed: `1121462652342910986`.
- Staging feed: `1121471544355455058`.

Each edit set only `archived=true`, with an audit-log reason identifying the
OpenGrep rollout. Discord's client rate-limit handling was retained, with
additional pacing between edits. Thread messages and locking state were
preserved. Already archived threads needed no changes. A final active-thread
query checked completion independently of individual edit responses.

At 12:19:35 UTC, the pass completed with 498 production threads and 486 staging
threads archived, zero failed edits, and zero remaining active threads in either
feed. Both final guild active-thread queries returned an empty list. The counts
reflect the live inventory at execution; some threads had already auto-archived
since the original incident inventory of 1,000 active threads.

Live Discord reads confirmed new production alerts contain one embed with the
OpenGrep field and Report, Suppress, and View findings actions. `ffrwd@0.21.1`
published in 42 seconds with no thread ID; complete and partial scan summaries
were both verified.

## Rollback

The previous production image was
`ghcr.io/vipyrsec/bot:sha-618f19e39b9fd6da469cf54b2b1da2f5c4a25c3b@sha256:f4fe759eda533218f4c8c815f8971494f8ca01aa4c506528f7f52490c0d5b2ce`.
Restoring it would restore the thread-dependent publisher. Stored OpenGrep
results remain in Mainframe, and archived Discord threads retain their history.
