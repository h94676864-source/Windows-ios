# Roadmap

## M0 — Foundation
- [x] Repository structure and project documentation.
- [x] SwiftUI app shell.
- [x] XcodeGen project specification.
- [x] macOS GitHub Actions simulator build.
- [ ] Confirm first green CI run on GitHub.

## M1 — iOS client foundations
- [ ] Session and API models.
- [ ] Keychain-backed authentication.
- [ ] Connection state machine and error handling.
- [ ] Remote display prototype.
- [ ] Hardware keyboard and pointer input.

## M2 — Cloud control plane
- [ ] Authentication and device registration.
- [ ] Session lifecycle API.
- [ ] Per-user isolated worker allocation.
- [ ] Persistent encrypted storage.
- [ ] Usage quotas and observability.

## M3 — Desktop workflows
- [ ] Linux desktop profile.
- [ ] Windows desktop profile.
- [ ] Clipboard and file transfer.
- [ ] VS Code remote workspace.
- [ ] User-managed IDA Pro Windows/Linux profiles.

## M4 — Performance and games
- [ ] WebRTC adaptive streaming.
- [ ] Audio and controller support.
- [ ] GPU worker provisioning.
- [ ] Game compatibility test matrix.
- [ ] Reconnect and session recovery tests.

## Release gates
- No credentials in source control.
- Authentication and session isolation tests pass.
- iPhone 14 real-device input and streaming tests pass.
- User-provided software licensing requirements documented.
- Cloud operating costs and data retention controls documented.
