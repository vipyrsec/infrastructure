# Auth0 Tenant Configuration for `dragonfly-mainframe-frontend`

## Purpose

This document standardizes how to configure Auth0 for
`dragonfly-mainframe-frontend` and `dragonfly-mainframe`.

It is derived from the current frontend and backend code, not from desired future behavior. Use
it when creating a new Auth0 tenant or when reproducing the same configuration in another tenant.

## What the code requires

The current implementation expects all of the following:

- Auth0 Authorization Code flow with PKCE
- A GitHub-backed login path, forced with the `connection` parameter
- An Auth0 access token whose:
  - `iss` matches `https://<AUTH0_DOMAIN>/`
  - `aud` matches the configured API audience
  - `exp` is present and unexpired
  - `sub` is present
- API permissions to be present in the access token, ideally as a `permissions` array
- Separate environment values for callback URLs and API audiences
- A confidential application client secret for the frontend server-side token exchange

The frontend does not currently use Auth0 logout, custom claims, or browser-side token storage.

## Required Auth0 objects

Create these objects for each hosted environment you operate.

### Applications

Create a Regular Web Application for each hosted frontend deployment.

Recommended names:

- `dragonfly-mainframe-frontend-staging`
- `dragonfly-mainframe-frontend-production`

For local development, reuse the staging application or create a dedicated development application.

### APIs

Create one Auth0 API per backend audience.

Recommended names:

- `dragonfly-mainframe-staging`
- `dragonfly-mainframe-production`

### Connection

Create or reuse a GitHub social connection. The frontend sends `connection=github` by default, so
the connection name should remain `github` unless `AUTH0_GITHUB_CONNECTION` is intentionally
changed in deployment configuration.

### Roles and permissions

Create these API permissions:

- `read:packages`
- `queue:packages`
- `report:packages`

Recommended roles:

- `dragonfly-reader`
  - `read:packages`
- `dragonfly-queue-operator`
  - `read:packages`
  - `queue:packages`
- `dragonfly-reporter`
  - `read:packages`
  - `report:packages`
- `dragonfly-admin`
  - `read:packages`
  - `queue:packages`
  - `report:packages`

`read:packages` should be included in every interactive user role. The frontend middleware denies
dashboard access entirely when that permission is missing.

## Environment matrix

Use these values exactly unless the application code changes.

- Local development
  - Frontend callback URL: `http://127.0.0.1:4321/auth/callback`
  - API audience: `https://dragonfly-staging.vipyrsec.com`
  - Mainframe base URL: `https://dragonfly-staging.vipyrsec.com`
- Staging
  - Frontend callback URL: `https://dashboard-staging.vipyrsec.com/auth/callback`
  - API audience: `https://dragonfly-staging.vipyrsec.com`
  - Mainframe base URL: `https://dragonfly-staging.vipyrsec.com`
- Production
  - Frontend callback URL: `https://dashboard.vipyrsec.com/auth/callback`
  - API audience: `https://dragonfly.vipyrsec.com`
  - Mainframe base URL: `https://dragonfly.vipyrsec.com`

If you split environments across separate tenants, reproduce the same per-environment values in
each tenant.

## Step-by-step tenant configuration

### 1. Create the backend API

In Auth0, create an API for each backend audience:

- Name: `dragonfly-mainframe-staging` or `dragonfly-mainframe-production`
- Identifier:
  - Staging: `https://dragonfly-staging.vipyrsec.com`
  - Production: `https://dragonfly.vipyrsec.com`
- Signing algorithm: `RS256`

After creating the API:

1. Enable `RBAC`.
2. Enable `Add Permissions in the Access Token`.
3. Add the permissions:
   - `read:packages`
   - `queue:packages`
   - `report:packages`

These settings are required because the frontend builds authorization state from access token
permissions and the backend validates the JWT against the configured Auth0 audience.

### 2. Create the frontend application

Create a Regular Web Application for each hosted deployment.

Recommended settings:

- Application type: `Regular Web Application`
- Token endpoint authentication method: keep a confidential client method enabled
- OIDC-conformant behavior: enabled

Set URLs as follows:

- Allowed Callback URLs:
  - Staging app: `https://dashboard-staging.vipyrsec.com/auth/callback`
  - Production app: `https://dashboard.vipyrsec.com/auth/callback`
  - If the same app is used for local development, also add:
    - `http://127.0.0.1:4321/auth/callback`
- Application Login URI:
  - Staging app: `https://dashboard-staging.vipyrsec.com/login`
  - Production app: `https://dashboard.vipyrsec.com/login`

Current code does not use Auth0 logout or browser-side CORS calls. Keep these tightly scoped:

- Allowed Logout URLs: leave empty unless an Auth0-hosted logout flow is introduced later
- Allowed Web Origins: leave empty unless a browser-side Auth0 SDK is introduced later
- Allowed Origins (CORS): leave empty unless a browser-side Auth0 SDK is introduced later

### 3. Enable only the intended connection

Enable the GitHub connection for the application.

For the frontend application:

- Disable database, passwordless, and other social connections unless explicitly required
- Leave only the GitHub connection enabled
- Keep the connection name aligned with `AUTH0_GITHUB_CONNECTION`

The frontend already forces the GitHub connection on `/authorize`, but the application should also
be limited in Auth0 so the tenant configuration matches the code path.

### 4. Configure GitHub login securely

Configure the GitHub social connection with an organization-controlled OAuth app and restrict
administration of that GitHub app.

Use a Post-Login Action to enforce organization membership. The frontend does not verify GitHub
organization membership itself, so this check belongs in Auth0.

Required Action secrets:

- `ALLOWED_GITHUB_ORG`
- `GITHUB_ORG_TOKEN`

`GITHUB_ORG_TOKEN` should be a GitHub token that can read organization membership for the target
organization.

Recommended Post-Login Action:

```js
exports.onExecutePostLogin = async (event, api) => {
  if (event.connection.strategy !== "github") {
    api.access.deny("Only GitHub login is allowed for this application.");
    return;
  }

  const identity = event.user.identities?.find((item) => item.provider === "github");
  const login =
    identity?.profileData?.login ||
    event.user.nickname ||
    event.user.username;

  if (!login) {
    api.access.deny("GitHub login is missing a username.");
    return;
  }

  const response = await fetch(
    `https://api.github.com/orgs/${event.secrets.ALLOWED_GITHUB_ORG}/memberships/${login}`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${event.secrets.GITHUB_ORG_TOKEN}`,
        "User-Agent": "vipyrsec-auth0-post-login"
      }
    }
  );

  if (response.status !== 200) {
    api.access.deny("GitHub organization membership is required.");
    return;
  }

  const membership = await response.json();
  if (membership.state !== "active") {
    api.access.deny("Active GitHub organization membership is required.");
  }
};
```

Bind this Action to the `Login / Post Login` trigger for every Dragonfly frontend application in
the tenant.

### 5. Create roles and assign permissions

Create the roles listed earlier and assign API permissions to them.

Operational guidance:

- Assign roles to named users or tightly controlled groups
- Do not rely on default broad access
- Avoid creating queue-only or report-only roles without `read:packages`, because those users will
  still be blocked from the dashboard

### 6. Assign users

For each approved operator:

1. Confirm their GitHub account is a member of the allowed organization.
2. Confirm the user can authenticate through the GitHub connection.
3. Assign one or more Dragonfly roles in Auth0.

### 7. Capture deployment secrets

Record the application and tenant values in the deployment platform.

For `dragonfly-mainframe-frontend`, set:

- `APP_ENV`
- `AUTH_MODE=auth0`
- `AUTH0_DOMAIN`
- `AUTH0_CLIENT_ID`
- `AUTH0_CLIENT_SECRET`
- `AUTH0_AUDIENCE`
- `AUTH0_CALLBACK_URL`
- `AUTH0_GITHUB_CONNECTION`
- `SESSION_SECRET`
- `MAINFRAME_API_BASE_URL`
- `AUTH0_PERMISSION_READ_PACKAGES=read:packages`
- `AUTH0_PERMISSION_QUEUE_PACKAGES=queue:packages`
- `AUTH0_PERMISSION_REPORT_PACKAGES=report:packages`

For `dragonfly-mainframe`, set:

- `auth0_domain`
- `auth0_audience`

The frontend and backend must agree on the same Auth0 domain and API audience for a given
environment.

### 8. Generate a distinct session secret per environment

Set a unique `SESSION_SECRET` for each deployment environment.

Requirements:

- High entropy
- Stored only in the deployment secret manager
- Never reused between staging and production

The frontend seals both the authenticated session cookie and the PKCE transient state cookie with
this value.

## Verification checklist

Complete this checklist for each environment.

### Auth0 objects

- [ ] A Regular Web Application exists for the environment
- [ ] An Auth0 API exists for the environment audience
- [ ] The API uses `RS256`
- [ ] `RBAC` is enabled on the API
- [ ] `Add Permissions in the Access Token` is enabled on the API
- [ ] The API defines `read:packages`
- [ ] The API defines `queue:packages`
- [ ] The API defines `report:packages`
- [ ] Only the intended GitHub connection is enabled for the application
- [ ] The Post-Login Action is deployed
- [ ] The Post-Login Action is attached to `Login / Post Login`
- [ ] The Post-Login Action secrets are populated

### Application URLs

- [ ] Allowed Callback URLs contain only the required environment callback URL
- [ ] `http://127.0.0.1:4321/auth/callback` is present only when intentionally allowing local login
- [ ] The Application Login URI points at the correct `/login` URL
- [ ] No unnecessary logout or browser origin entries are present

### Authorization model

- [ ] Auth0 roles have been created
- [ ] Roles map to the correct API permissions
- [ ] Every interactive role includes `read:packages`
- [ ] Only approved users have been assigned Dragonfly roles

### Deployment configuration

- [ ] Frontend `AUTH0_DOMAIN` matches the tenant domain
- [ ] Frontend `AUTH0_CLIENT_ID` and `AUTH0_CLIENT_SECRET` match the environment application
- [ ] Frontend `AUTH0_AUDIENCE` matches the environment API identifier
- [ ] Frontend `AUTH0_CALLBACK_URL` matches the environment callback URL
- [ ] Frontend `AUTH0_GITHUB_CONNECTION` matches the Auth0 connection name
- [ ] Frontend `SESSION_SECRET` is unique for the environment
- [ ] Backend `auth0_domain` matches the same tenant
- [ ] Backend `auth0_audience` matches the same API identifier

### Functional verification

- [ ] Browsing to `/login` redirects to Auth0
- [ ] The Auth0 authorize request includes the expected `connection` value
- [ ] The Auth0 authorize request includes the expected `audience`
- [ ] Login succeeds only for users in the allowed GitHub organization
- [ ] A user with `read:packages` can load the dashboard
- [ ] A user without `read:packages` is redirected to `/access-denied`
- [ ] A user with `queue:packages` can queue packages
- [ ] A user without `queue:packages` receives a permission failure for queue operations
- [ ] A user with `report:packages` can report packages
- [ ] A user without `report:packages` receives a permission failure for report operations

## Rotation and change control

When rotating Auth0 configuration:

1. Rotate `AUTH0_CLIENT_SECRET` in Auth0 and in deployment secrets together.
2. Rotate `SESSION_SECRET` independently per environment.
3. Re-test login and permission-gated flows after every application, API, connection, or Action
   change.

Do not change callback URLs, audiences, permission names, or the GitHub connection name without a
corresponding application code review.
