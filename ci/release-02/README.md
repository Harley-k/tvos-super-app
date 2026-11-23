# SuperTV exact-source dual-platform smoke

Overlay only these new paths onto the dedicated public repository. Do not delete or replace the existing README, v0.1.0 source, or v0.1.0 Actions workflow. No personal Mac or company repository is involved.

The only new workflow trigger is workflow_dispatch on the default branch. Input the exact commit SHA containing this snapshot. It verifies HEAD, event SHA, every original 0.2.0 source byte and the file list before running. A single ARM64 macos-26 job uses preinstalled Xcode 26.5 and tvOS 26.5; no platform downloads, retries, artifact uploads, paid storage, or Apple account. The timeout is 15 minutes, not a billing switch; run only upon user approval using the standard free public-repository runner; do not provision paid or larger runners.

## Evidence and timing

- macOS native build, runner-only ad-hoc signing, native app process launch for 5 seconds, check bundled media bytes; automatically terminate only that PID. This is not GUI navigation evidence.
- Independent macOS AVFoundation CLI uses the real built app media, verifies decoded pixel buffers, measures actual time progression, seeks to a stored position, and checks that the next episode starts independently. Probe is silent; 65s watchdog. No product code is modified.
- Simulator boots in parallel with the Mac stage. Three existing tvOS XCTest scenarios run sequentially using remote input. Separate logs; overall pass needs every stage. A timeout may suppress the final summary.
- Rough estimate: checkout/setup under 2 min, native build and probe 1–3 min, tvOS build and tests 3–7 min; 5–12 total on a healthy runner, no guarantee. The 15-minute cap always applies. Never auto-rerun.
- Local ad-hoc .app launch does not validate Gatekeeper, customer distribution or notarization. Independent distribution to other Macs normally requires Developer ID and Apple notarization. No credentials, identities, signing certificates, App Store submission, physical Apple TV installation, or build uploads.
- Neither stage verifies the user's Mac/TV, playback via outside catalogs, real provider integrations, or listening to audio.

[Apple Guide: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/)
