# Dragonfly Loader Staging Cloudflare Access

This note records the direct staging secret rotation required to migrate
`dragonfly-loader` from Auth0 to Cloudflare Access service-token headers.

Applied on:

- `2026-04-04`

Staging Kubernetes secret:

- `dragonfly/dragonfly-loader-env`

Cloudflare Access token source:

- token name: `dragonfly-loader-staging`
- token id: `81f1ecf8-44b1-4636-9b13-a2ab077588d1`
- created in Cloudflare account `Vipyr Security`
- expires at: `2027-04-04T17:58:56Z`

Secret contract after rotation:

- `BASE_URL=https://dragonfly-staging.vipyrsec.com`
- `CF_ACCESS_CLIENT_ID`
- `CF_ACCESS_CLIENT_SECRET`

Deprecated keys removed from the staging secret:

- `AUTH0_DOMAIN`
- `CLIENT_ID`
- `CLIENT_SECRET`
- `USERNAME`
- `PASSWORD`
- `AUDIENCE`

Notes:

- Secret values are intentionally omitted from this file.
- Cloudflare Access for `dragonfly-staging.vipyrsec.com` already had a
  `non_identity` policy allowing `any_valid_service_token` at the time of
  rotation.
