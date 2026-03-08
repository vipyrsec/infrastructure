# Auth Environment Segmentation

Audit date: 2026-03-08

This document captures the current state of frontend access across Auth0, Cloudflare, DigitalOcean,
and the local Dragonfly repositories. It also defines the target staging and production split and
the promotion steps required to keep those environments isolated.

## Current State

### Auth0

- The active tenant is `vipyrsec.us.auth0.com`.
- The tenant currently contains one regular web application for the frontend:
  `Dragonfly Frontend`.
- That application currently allows only the local callback
  `http://127.0.0.1:4321/auth/callback`.
- The tenant currently contains one Dragonfly API resource server with identifier
  `https://dragonfly.vipyrsec.com`.
- There is no separate staging API audience and no separate staging regular-web application in the
  live tenant.
- A post-login action named `Github Login Validation` exists and is scoped to the
  `Dragonfly Frontend` application. It enforces GitHub login and checks active membership in the
  `vipyrsec` GitHub organization.

### DigitalOcean

- Separate Kubernetes clusters already exist for `staging` and `prod`.
- Both clusters are in `sfo3`.
- This means the compute boundary already exists. The missing split is primarily identity and
  frontend routing, not cluster tenancy.

### Cloudflare

- DNS records exist for:
  - `dragonfly-staging.vipyrsec.com`
  - `dragonfly.vipyrsec.com`
- I did not find DNS records for:
  - `dashboard-staging.vipyrsec.com`
  - `dashboard.vipyrsec.com`
- Zone listing worked, but Cloudflare Access application inspection returned an authentication
  error. Access policy state still needs direct verification in the Cloudflare dashboard or with a
  token that includes Access scopes.

### Local Repositories

- `dragonfly-mainframe-frontend` previously supported only:
  - local development Auth0
  - local development mock auth
  - hosted production Auth0
- `dragonfly-loader` still defaults to the production Auth0 tenant and production API audience.
- `security-intelligence/scripts` hard-codes the production Auth0 tenant and production
  `update-rules` endpoint.
- `dragonfly-mainframe` is already environment-driven for Auth0 issuer and audience. It does not
  need code changes to support separate staging and production tenants.

## Target State

The target deployment model is:

- `dashboard-staging.vipyrsec.com`
  - frontend hostname for staging
  - Auth0 callback: `https://dashboard-staging.vipyrsec.com/auth/callback`
  - Auth0 tenant: staging tenant only
  - API audience: `https://dragonfly-staging.vipyrsec.com`
  - backend API: `https://dragonfly-staging.vipyrsec.com`

- `dashboard.vipyrsec.com`
  - frontend hostname for production
  - Auth0 callback: `https://dashboard.vipyrsec.com/auth/callback`
  - Auth0 tenant: production tenant only
  - API audience: `https://dragonfly.vipyrsec.com`
  - backend API: `https://dragonfly.vipyrsec.com`

Rules for the split:

- staging frontend must never use production Auth0 credentials
- staging frontend must never request production audience tokens
- production frontend must never point at staging callback or staging API hosts
- staging and production session secrets must be different
- staging and production Auth0 applications must register only their own callback and logout URLs

## Repository Changes

The frontend now supports a first-class hosted staging runtime:

- `APP_ENV=staging` activates `STAGING_*` variables
- `APP_ENV=production` activates `PROD_*` variables
- local development continues to use `DEV_*`
- hosted staging rejects production callback and API hosts
- hosted production rejects staging callback and API hosts

This is necessary because `import.meta.env.PROD` alone cannot distinguish a deployed staging build
from a deployed production build.

## Required External Changes

These changes are still required outside the repo.

### 1. Create a staging Auth0 tenant

Use a dedicated tenant such as `vipyrsec-staging.us.auth0.com`.

Replicate from production:

- GitHub social connection
- RBAC-enabled Dragonfly API
- the `read:packages`, `queue:packages`, and `report:packages` scopes
- roles that map to those scopes
- the GitHub membership post-login action

Do not reuse:

- client IDs
- client secrets
- session secrets
- API identifiers

### 2. Create a staging regular-web application

Recommended name: `Dragonfly Frontend Staging`

Register only:

- callback URL: `https://dashboard-staging.vipyrsec.com/auth/callback`
- logout URL: `https://dashboard-staging.vipyrsec.com/login`
- web origin: `https://dashboard-staging.vipyrsec.com`

Production should keep only:

- callback URL: `https://dashboard.vipyrsec.com/auth/callback`
- logout URL: `https://dashboard.vipyrsec.com/login`
- web origin: `https://dashboard.vipyrsec.com`

### 3. Create a staging Auth0 API

Recommended identifier: `https://dragonfly-staging.vipyrsec.com`

Mirror the production scopes:

- `read:packages`
- `queue:packages`
- `report:packages`

Enable:

- RBAC
- `Add Permissions in the Access Token`

### 4. Publish frontend DNS and TLS

Create DNS records and certificates for:

- `dashboard-staging.vipyrsec.com`
- `dashboard.vipyrsec.com`

Cloudflare should proxy both records and terminate TLS for both.

### 5. Verify Cloudflare Access posture

If Cloudflare Access protects the frontend or backend, ensure:

- staging and production applications are separate
- policy audiences are different per environment
- service tokens are not shared across environments
- staging policies cannot reach production hostnames

## Promotion Flow

### Promote to staging

1. Deploy backend changes to the staging Kubernetes cluster.
2. Apply staging backend secrets:
   - `auth0_domain`
   - `auth0_audience`
   - `client_origin_url`
3. Deploy the frontend with:
   - `APP_ENV=staging`
   - `STAGING_AUTH0_*`
   - `STAGING_SESSION_SECRET`
   - `STAGING_MAINFRAME_API_BASE_URL=https://dragonfly-staging.vipyrsec.com`
4. Confirm Auth0 staging callbacks and logout URLs match the staging frontend hostname.
5. Run an end-to-end login and package lookup against staging.

### Promote to production

1. Promote the backend artifact to the production Kubernetes cluster.
2. Apply production backend secrets:
   - `auth0_domain`
   - `auth0_audience`
   - `client_origin_url`
3. Deploy the frontend with:
   - `APP_ENV=production`
   - `PROD_AUTH0_*`
   - `PROD_SESSION_SECRET`
   - `PROD_MAINFRAME_API_BASE_URL=https://dragonfly.vipyrsec.com`
4. Confirm Auth0 production callbacks and logout URLs match the production frontend hostname.
5. Run an end-to-end login and package lookup against production.

## Mock Auth Versus Real Promotion

Mock auth is only appropriate for local UI development. It does not validate:

- Auth0 callback routing
- GitHub organization enforcement
- role-to-scope mapping
- API audience validation
- cookie domain and TLS behavior

Anything intended for staging or production promotion must be exercised with real Auth0 and the
matching environment-specific API audience.

## Follow-Up Work

- Parameterize `dragonfly-loader` defaults away from production.
- Replace hard-coded production URLs in `security-intelligence/scripts`.
- Re-run a Cloudflare Access inventory using a token with Access scopes.
