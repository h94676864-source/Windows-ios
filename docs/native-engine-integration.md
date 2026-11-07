# Native Windows Runtime Integration — Madeira Pin

Status: source pinned for compatibility research; **not linked into the app or shipped in the IPA**.

## Pinned upstream

- Repository: https://github.com/willfaust/Madeira
- Commit: `8b52c1810a0b77614238001ed86199978865afd1`
- Local checkout path: `Vendor/Madeira`
- Stack: FEX-Emu (x86/x86-64 to ARM64), Wine ARM64EC/WoW64, DXMT (D3D9/10/11 to Metal), and Madeira's D3D12 implementation.

The vendor entry is a Git submodule pinned to an immutable commit. The normal iOS build does not recurse into it and does not compile it, so the existing app build remains isolated from upstream build dependencies.

## Compatibility blockers to resolve

1. Madeira upstream currently documents iOS 26+ as the only reliably working OS. This project remains at iOS deployment target 18.5; compatibility is unproven.
2. JIT is required by FEX. Upstream documents debugger-attached JIT; the app does not yet contain a verified JIT enablement path.
3. The upstream build is multi-stage and depends on toolchains and generated inputs not all present in a clean clone. Its own BUILDING.md records clean-clone gaps and unverified steps.
4. Upstream .gitmodules points at custom FEX, Wine, DXMT and madeira-dock forks. Do not assume a recursive clone/build is reproducible until each fork and nested dependency is verified.
5. GPL/LGPL and third-party redistribution obligations must be reconciled before shipping compiled components.

## Integration sequence

- [ ] Verify iOS 18.5 API/SDK compatibility on a real iPhone.
- [ ] Establish a supported JIT path and prove FEX can execute a minimal x86-64 test.
- [ ] Build Wine ARM64EC + WoW64 in-process and run wine self-tests.
- [ ] Integrate the runtime behind the existing Wine adapter ABI; bundle signed device-compatible frameworks/resources.
- [ ] Run EXE/MSI installation and launch tests on-device.
- [ ] Integrate DXMT/D3D12 and validate real Direct3D workloads.
- [ ] Add reproducible CI builds and licence notices/source offers for redistributed components.

## Important status semantics

A present submodule is source availability only. It does not mean Wine, FEX, DXMT, JIT, or Windows EXE execution is operational. The app's readiness UI must continue to report the runtime unavailable until the actual engine payload passes its ABI self-test and an on-device launch test.
