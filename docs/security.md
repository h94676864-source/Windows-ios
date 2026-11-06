# Security baseline

- Do not commit cloud credentials, API tokens, Apple signing keys, certificates, provisioning profiles, IDA installers, or licence files.
- Use GitHub Actions secrets or a dedicated secret manager for deployment credentials.
- Use TLS for all client/control-plane traffic.
- Use short-lived, scoped session credentials.
- Isolate each user/session compute environment.
- Encrypt persistent user volumes and backups.
- Require explicit authorization for file transfer and clipboard sharing.
- Apply resource quotas, session expiration, and audit logging.
- Keep Windows/Linux worker management interfaces on private networks.
- Publish supported data retention and deletion behavior before production use.

Security review is required before exposing a public multi-user backend.
