# Local compatibility preservation

This branch is separate from the portable controller-audio feature branch. It
restores the original working customization set, not just the speaker feature.
Original feature snapshot: `102fc2b4519db1186c05c49d0cd57ed37d32a05d`.
The additional 14-file snapshot remains independently recoverable on
`recovery/custom-source-snapshot` (`d5e3c0c626be9ddd76bdbb36516bba4a76deba5a`).
No private configuration, pairing identities, SDK archives, logs or binaries
belong in this repository.

## File-by-file reconciliation

| Original dirty file | Behavior retained here | Verification / qualification |
| --- | --- | --- |
| `cmake/dependencies/FetchRtxVideoSdk.cmake` | Explicit local SDK root and required-file checks | Local Release configure; supplied SDK is not automatically authenticated |
| `cmake/dependencies/rtx_video_adapter.cmake` | Existing prebuilt adapter option | Requires explicit adapter/runtime hashes; no unnecessary MSVC configure in prebuilt mode; build-time hashes rechecked |
| `scripts/build-ds5-sidecar.ps1` | First PATH match for dotnet | Source-preservation check; Release sidecar build |
| `src/entry_handler.cpp` | Codex service lookup | Source-preservation check |
| `src/platform/windows/input.cpp` | Auto promotes PS + native DS5 PCM capability to DS5 when component exists | Compiled selection tests; helper extraction preserves predicate; no game detection |
| `src/stream.cpp` | 1 ms polling while DS5 PCM active | Source-preservation check; idle interval unchanged; hardware CPU/latency measurement still needed |
| `src/video.cpp` | Five-second capture/encode cadence diagnostics | Source-preservation check; runtime diagnostics retained |
| `src_assets/windows/misc/autostart/autostart-service.bat` | Dedicated Codex service autostart | Source-preservation check; never executed during tests |
| `src_assets/windows/misc/service/install-service.bat` | Codex identity/config location; no removal of other Sunshine services | Source-preservation check; never executed during tests |
| `src_assets/windows/misc/service/uninstall-service.bat` | Removes only Codex service; no shared image-name kill | Source-preservation check; never executed during tests |
| `tools/sunshine-ds5-sidecar/DualSenseHapticsAudio.cs` | Composite Joystick HID usage, inherited by Genshin profile | Sidecar self-check compares report/interfaces and usage prefix |
| `tools/sunshine-ds5-sidecar/ProtocolSelfTest.cs` | Original profile-invariant checks | Retained alongside new protocol and queue regressions |
| `tools/sunshine-ds5-sidecar/README.md` | Original Joystick/Genshin explanation | Retained alongside speaker/queue contract documentation |
| `tools/sunshinesvc.cpp` | Codex service name and isolation | **Intentional adjustment:** original blanket GUI auto-launch suppression is replaced by normal user-session supervision, because the user explicitly requires the tray; deliberate GUI quit remains respected within a core lifecycle |

## Build and dependency parity

Use preset `local-compat-release`: **Release**, RTX HDR **ON**, GUI tray **ON**,
legacy in-process tray **OFF**, tests **ON**, driver downloads **OFF**. Supply
`RTX_VIDEO_SDK_LOCAL_ROOT`, `RTX_VIDEO_ADAPTER_PREBUILT`,
`RTX_VIDEO_ADAPTER_EXPECTED_SHA256` and `RTX_VIDEO_RUNTIME_EXPECTED_SHA256`
explicitly. A missing RTX dependency is a configuration failure, not a silent
fallback to an RTX-disabled build. Configure from the repository working directory.
The preset does not install or restart applications.

Public common dependency is `61bb873bdc32bdc998d667bf55d86a3d95a1cd16`,
not the unpublished original `7b147368ab34d09c43a4e87ff9659eef53a0158c`.
The public dependency adds the complete validated quad receiver and optional
speaker negotiation; its video loss-recovery differences do not enter the host's
build, which consumes common headers, ENet and selected haptics code rather than
the client video receiver. Compare both dependency histories before client rollout.
Public panel dependency is `09c94a83c654e45cf07f2b9cb617da39dfa6a548`.
Tray-owner tests compile with the same tray definitions as the host.

## Supply-chain and licensing limits

An expected digest detects changes; it does not prove that an unsigned adapter is
safe or grant redistribution rights. Verify original acquisition/release metadata
separately. Validate the NVIDIA runtime Authenticode signature and retain the exact
SDK license locally. NVIDIA RTX SDK terms impose separate distribution and
attribution requirements and restrictions on open-source licensing interactions.
A DLL boundary alone is not a compatibility determination. Do not publish bundled
SDK/runtime/adapter binaries until their distribution obligations are resolved.
No driver, certificate, trust-store, firewall or credentials are changed here.

## Remaining live-validation gates

Builds and self-checks do not demonstrate game compatibility, controller routing,
Bluetooth sound quality, 1 ms polling CPU cost, RTX activation, or 4K/VRR cadence.
Preserve the currently running installation and its private configuration until
the exact committed/published tree, build inputs, hashes and test results have
been reviewed and a coordinated replacement or rollback is explicitly planned.
