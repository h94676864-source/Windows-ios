# Winlator-iOS

A native iPhone client for cloud-hosted Windows and Linux desktops, with a touch-first desktop interface, remote development workspaces, reverse-engineering workstations, and game-streaming support.

> **Project status:** iOS client foundation. This repository does not run Windows/Linux locally on iOS and does not yet include a production cloud service. Full desktop applications are intended to execute in isolated cloud machines and stream to the iPhone.

## Product direction

- Native iOS launcher and desktop shell (SwiftUI).
- Remote Windows and Linux sessions.
- Keyboard, pointer, touch, clipboard, and file-transfer support.
- Persistent VS Code development workspaces.
- User-provided, properly licensed IDA Pro installations in Windows/Linux cloud workstations.
- GPU-backed game streaming as a later milestone.

## Architecture

See [docs/architecture.md](docs/architecture.md), [docs/control-plane-api.md](docs/control-plane-api.md), and [docs/roadmap.md](docs/roadmap.md).

## Build

1. Push changes to GitHub.
2. GitHub Actions uses a hosted macOS Intel runner and Xcode to build for generic iOS devices.
3. Download the `WinlatorIOS-Unsigned-IPA` artifact from the successful workflow run.
4. Configure Apple signing and provisioning before installing on a physical iPhone.

The workflow packages an **unsigned device IPA**, not a simulator build. An unsigned IPA is a build artifact; it is not directly installable on a normal iPhone until it is signed with a valid certificate and provisioning profile.

## Requirements

- Xcode and the iOS SDK on a macOS build runner.
- XcodeGen (installed by the workflow).
- Apple Developer signing setup for device distribution.
- A separately deployed backend and Windows/Linux compute infrastructure for remote sessions.

## Current app

The SwiftUI app contains Home, Workspaces, Files, and Settings tabs. Workspace list/create/stop requests use the documented control-plane API. The backend URL is configured in Settings, and its bearer token is stored in the iOS Keychain. The Files tab and live remote desktop transport remain planned; no cloud machine is provisioned by this repository alone.

## Security

Never commit API keys, cloud credentials, signing certificates, provisioning profiles, IDA installers, licence files, or user binaries. Backend access tokens are stored in iOS Keychain. See [docs/security.md](docs/security.md).

## License

No project-wide license has been selected yet. Individual upstream components retain their own licenses and notices. Do not assume the original Winlator license automatically applies to every component in this repository.
