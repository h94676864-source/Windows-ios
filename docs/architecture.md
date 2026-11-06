# Architecture

## Core decision

Winlator-iOS is a native iOS client for remote desktop workloads. iOS is the control, display, input, and file-management surface. Full Windows/Linux desktop software executes in isolated remote machines.

This avoids treating iOS as an unrestricted PC hypervisor and gives demanding desktop applications access to the operating system and hardware they expect.

## Components

### iOS client
- SwiftUI navigation and launcher.
- Session connection state machine.
- Remote display surface.
- Touch-to-pointer and virtual keyboard mapping.
- Hardware keyboard and supported controller input.
- Clipboard and explicit file-transfer UI.
- Secure token storage using Keychain.

### Control plane (planned)
- Authentication and device/session authorization.
- Session create/list/stop APIs.
- Per-user quotas and lifecycle management.
- Short-lived connection credentials.
- Audit events and health reporting.

### Compute plane (planned)
- Windows worker images.
- Linux worker images.
- Persistent encrypted user volumes.
- Optional GPU-enabled workers for games and graphics workloads.
- Separate profiles for development and reverse-engineering environments.

### Streaming plane (planned)
- WebRTC-based interactive streaming.
- Input channel for pointer, keyboard, and controller events.
- Adaptive bitrate and reconnect handling.
- Clipboard and file transfer over separately authorized channels.

## Workload profiles

- Windows desktop: Windows VM, user-managed software installation.
- Linux desktop: Linux VM, user-managed software installation.
- VS Code: persistent Linux or Windows development workspace.
- IDA Pro: user-provided licensed installation in a compatible Windows/Linux VM. No IDA binaries or licence material are bundled.
- Gaming: GPU-backed remote worker; game compatibility depends on GPU, drivers, anti-cheat, DRM, and network conditions.

## Network and security boundaries

The iOS app must authenticate to the control plane over TLS. The control plane issues short-lived session credentials. Compute workers are isolated per session/user. Never expose worker management ports directly to the public internet.

## Current implementation status

The repository currently contains only the native UI shell and CI scaffold. No backend, VM orchestration, streaming transport, authentication, or remote execution is implemented yet.
