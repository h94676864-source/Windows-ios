# Winlator-iOS

A native iPhone client for cloud-hosted Windows and Linux desktops, with a touch-first desktop interface, remote development workspaces, reverse-engineering workstations, and game-streaming support.

> **Project status:** Foundation scaffold. This repository does not yet run Windows/Linux locally on iOS and does not yet include a production cloud service. Full desktop applications are planned to execute in isolated cloud machines and stream to the iPhone.

## Product direction

- Native iOS launcher and desktop shell (SwiftUI).
- Remote Windows and Linux sessions.
- Keyboard, pointer, touch, clipboard, and file-transfer support.
- Persistent VS Code development workspaces.
- User-provided, properly licensed IDA Pro installations in Windows/Linux cloud workstations.
- GPU-backed game streaming as a later milestone.

## Architecture

See [docs/architecture.md](docs/architecture.md) and [docs/roadmap.md](docs/roadmap.md).

## Build from an iPhone

1. Edit files in GitHub's web editor or a browser-based development environment.
2. Push changes to GitHub.
3. GitHub Actions uses a hosted macOS runner and Xcode to build the iOS app.
4. Configure Apple signing secrets before attempting a signed distribution build.

The initial workflow builds an unsigned simulator application. Device installation requires signing and provisioning configured by the repository owner.

## Requirements

- Xcode and the iOS SDK on a macOS build runner.
- XcodeGen (installed by the workflow).
- An Apple Developer signing setup for device distribution.
- A separately deployed backend and Windows/Linux compute infrastructure for remote sessions.

## Current app

The initial SwiftUI app is a navigable shell with Home, Workspaces, Files, and Settings tabs. Remote session creation is intentionally represented as a not-yet-configured state until a backend endpoint and authentication flow are implemented.

## Security

Never commit API keys, cloud credentials, signing certificates, provisioning profiles, IDA installers, licence files, or user binaries. See [docs/security.md](docs/security.md).

## License

No project-wide license has been selected yet. Individual upstream components retain their own licenses and notices. Do not assume the original Winlator license automatically applies to every component in this repository.
