# Dragonfly Cloudflare Access Migration

## Scope and invariants

This runbook migrates the deployed Dragonfly API and its machine callers to
Cloudflare Access. The frontend and feed repositories are not deployed and are
outside this rollout.

The following rules are mandatory:

- staging and production use separate Access applications and audiences
- every machine caller uses a token created for only one environment
- policies select named service tokens; `any valid service token` is forbidden
- callers use the public Cloudflare-protected hostname, never a forwarded or
  directly enumerable origin
- Kubernetes Secret values remain cluster-local and are never committed
- application and infrastructure PRs are approved before either environment is
  changed
- staging passes the complete route matrix before production is modified

## Environment boundaries

| Property | Staging | Production |
| -------- | ------- | ---------- |
| Public API | `https://dragonfly-staging.vipyrsec.com` | `https://dragonfly.vipyrsec.com` |
| Access application | Dragonfly Mainframe Staging | Dragonfly Mainframe Production |
| Access audience | Unique staging audience | Unique production audience |
| Human policy | Active `vipyrsec` GitHub organization members | Active `vipyrsec` GitHub organization members |
| Machine policies | Named staging service tokens only | Named production service tokens only |
| Kubernetes context | `do-sfo3-staging` | `do-sfo3-prod` |

The Cloudflare team domain is tenant-wide and may be the same in both
environments. Application audiences, service-token IDs, service-token secrets,
and Kubernetes Secret values must be different.

## Pre-cutover evidence handling

Keep the environment inventory and validation evidence in the private change
record. Do not publish application, audience, policy, or token identifiers;
exact runtime policy posture; secret values; or non-routed preparation
hostnames in this repository.

The private record must identify the existing application to update at cutover
so operators do not create a duplicate application or audience.

## Protected route inventory

All routes below must reject a missing assertion, a legacy bearer credential,
and an invalid Cloudflare assertion. Each consuming client must also prove its
exact method, path, and Cloudflare service-token headers.

| Method | Path | Known callers |
| ------ | ---- | ------------- |
| `GET` | `/rules` | scanner |
| `GET` | `/package` | bot |
| `GET` | `/reported-packages` | interactive or administrative clients |
| `POST` | `/jobs` | scanner |
| `POST` | `/batch/package` | loader |
| `POST` | `/package` | bot or administrative clients |
| `PUT` | `/package` | scanner |
| `POST` | `/report` | bot |
| `POST` | `/update-rules/` | security-intelligence workflow |

## Cloudflare resources

For each environment:

1. Create one self-hosted Access application for only that environment's API
   hostname.
2. Record its audience in the matching `dragonfly-mainframe-env` Secret as
   `CF_ACCESS_AUDIENCE`.
3. Configure `CF_ACCESS_TEAM_DOMAIN` from the tenant's Access team domain.
4. Create a human Allow policy restricted to active members of the
   `vipyrsec` GitHub organization.
5. Create one service token per deployed caller.
6. Create machine Allow policies that include only the exact named token for
   that caller and application.
7. Remove broad service-token policies only after all named policies have been
   validated.

Suggested token names:

- `dragonfly-loader-staging` and `dragonfly-loader-production`
- `dragonfly-client-staging` and `dragonfly-client-production`
- `dragonfly-bot-staging` and `dragonfly-bot-production`
- `security-intelligence-production`

Security Intelligence deploys rules only to production. Do not create a
staging token unless a separately reviewed staging workflow is introduced.

## Secret contracts

Secret object names may match across clusters because the Kubernetes clusters
are separate. Their values must not.

### `dragonfly-mainframe-env`

- `CF_ACCESS_AUDIENCE`: created by the matching Access application
- `CF_ACCESS_TEAM_DOMAIN`: Cloudflare Zero Trust team domain
- existing database, GitHub, mailer, and Sentry values remain environment-local

### `dragonfly-loader-env`

- `BASE_URL`: matching public API URL
- `CF_ACCESS_CLIENT_ID`: matching loader service token
- `CF_ACCESS_CLIENT_SECRET`: matching loader service token

### `dragonfly-client-env`

- `DRAGONFLY_BASE_URL`: matching public API URL
- `DRAGONFLY_CF_ACCESS_CLIENT_ID`: matching scanner service token
- `DRAGONFLY_CF_ACCESS_CLIENT_SECRET`: matching scanner service token

### `bot-env`

- `DRAGONFLY_API_URL`: matching public API URL
- `CF_ACCESS_CLIENT_ID`: matching bot service token
- `CF_ACCESS_CLIENT_SECRET`: matching bot service token

### GitHub environment `dragonfly-production`

The security-intelligence workflow uses:

- secret `CF_ACCESS_CLIENT_ID`
- secret `CF_ACCESS_CLIENT_SECRET`
- variable `DRAGONFLY_API_URL=https://dragonfly.vipyrsec.com`

These values must not be copied into a staging GitHub environment.

## Pre-change gates

Before changing staging:

- all application PRs are manually approved and merged
- every protected backend route has negative authentication coverage
- every deployed caller has exact route and header coverage
- repository-wide legacy-provider searches have no in-scope matches
- workflow audits report no findings
- immutable image SHAs exist for every changed workload
- current Cloudflare application, policy, token, DNS, Kubernetes image, and
  Secret-key inventories are recorded in the private change record without
  secret values
- rollback image SHAs and prior Cloudflare policy identifiers are recorded in
  the private change record

## Staging rollout

1. Confirm `doctl` context `vipyr` and Kubernetes context
   `do-sfo3-staging`.
2. Create or reconcile the staging Access application and named policies.
3. Create staging-only service tokens and write them directly to the matching
   staging Kubernetes Secrets.
4. Set the staging mainframe audience and team domain.
5. Apply reviewed manifests and immutable application images.
6. Wait for rollouts and the next loader CronJob; do not start duplicate Jobs.
7. Exercise all nine protected routes:
   - unauthenticated requests are rejected
   - legacy bearer requests are rejected
   - invalid assertions are rejected
   - valid human or service-token requests reach the application
8. Confirm loader `POST /batch/package`, scanner `GET /rules`, scanner
   `POST /jobs`, scanner `PUT /package`, and all three bot routes succeed.
9. Confirm application logs and Sentry contain no authentication regression,
   crash loop, or unexpected origin traffic.
10. Observe at least two scheduled loader executions with no overlapping or
    stuck Job.

## Production rollout

Production begins only after staging passes and its evidence is recorded.

1. Confirm `doctl` context `vipyr` and Kubernetes context `do-sfo3-prod`.
2. Create the production Access application, named policies, and production-only
   service tokens.
3. Write production values directly to production Kubernetes Secrets and the
   `dragonfly-production` GitHub environment.
4. Apply the same reviewed manifest revision and application commits proven in
   staging.
5. Repeat the complete route and caller validation matrix.
6. Confirm the loader schedule, scanner queue depth, result submissions,
   security-intelligence rule update, logs, and Sentry.
7. Compare staging and production manifests, Secret key names, Access policy
   shapes, and image commits. Only environment-specific hostnames, audiences,
   token identities, and secret values may differ.

## Rollback

If application validation fails:

1. restore the prior immutable workload image
2. keep Access enforcement enabled
3. restore only the previous environment-specific Kubernetes Secret values
4. verify unauthenticated origin access remains impossible

If an Access policy blocks a valid caller:

1. restore the previously recorded policy by identifier
2. do not introduce an `any valid service token` policy
3. rotate any token whose value may have been exposed during diagnosis

Do not roll back to the legacy provider or reintroduce a runtime authentication
bypass.

## Completion evidence

Record runtime evidence in the private change record:

- merged application and infrastructure commit SHAs
- immutable image SHAs deployed to each cluster
- Access application and policy identifiers, excluding secret values
- Kubernetes Secret object names and key names, excluding values
- route-matrix results for staging and production
- loader schedules and scanner result timestamps
- Sentry issue or event links used for validation
- removal of obsolete legacy-provider configuration and credentials

The public infrastructure repository should contain only the reviewed
configuration contract, rollout procedure, and a high-level completion record.
Do not copy the private runtime inventory into a commit, pull request, issue,
workflow log, or review comment.
