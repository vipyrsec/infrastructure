# Dragonfly Client

Modular compute nodes capable of scanning packages and sending results upstream to a control server, written in Rust.

## Secrets

This deployment expects a number of secrets and environment variables to exist in a secret called
`dragonfly-client-secrets`.

| Environment   | Description                   |
| ------------- | ----------------------------- |
| CLIENT_ID     | Part of the OAuth credentials |
| CLIENT_SECRET | Part of the OAuth credentials |
| USERNAME      | Part of the OAuth credentials |
| PASSWORD      | Part of the OAuth credentials |
