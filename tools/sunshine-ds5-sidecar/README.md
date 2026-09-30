# Sunshine virtual device host

This optional Windows helper isolates Sunshine from the third-party
HIDMaestro runtime. The shipping executable remains
`Sunshine.Ds5Sidecar.exe` for component-upgrade compatibility, while the
process now uses a `VirtualDeviceHostServer` and `DeviceRegistry` internally.
It owns virtual devices and exposes the versioned `SDS5` named-pipe protocol.
The helper does not contain HIDMaestro binaries.

Build against the pinned upstream v1.7.3 runtime:

```powershell
dotnet build -c Release `
  -p:HIDMaestroCorePath=C:\path\to\HIDMaestro.Core.dll
```

Read-only capability probe:

```powershell
dotnet Sunshine.Ds5Sidecar.dll --probe
```

Deterministic protocol ABI, microphone queue/runtime-contract, four-channel
layout, and channel-isolation checks (no elevation or virtual device required):

```powershell
dotnet Sunshine.Ds5Sidecar.dll --self-check
```

The production process must be launched elevated and placed in the Sunshine
Job Object. The pipe accepts a single elevated client of the creating user;
non-elevated callers are rejected at connect time and dropped without
ending the sidecar.
Disconnecting the owning pipe disposes every device created by
that connection. Standard `dualsense` uses UMDF2; `dualsense-composite`
enables the USB composite HID/audio profile and authored haptics PCM.
For composite sessions, the sidecar also forwards the complete 48 kHz,
four-channel stream: channels 1/2 contain game-authored controller-speaker
audio and channels 3/4 contain the native actuator signal. The sidecar also
emits the legacy stereo haptics message so older cores and clients retain
native haptics.

Sunshine forwards the quad stream only when the client negotiates feature bit
`0x20` and `ds5_controller_audio` is enabled in `ds5_config.json` (the default).
Setting it to `false` is a per-session compatibility preference. The saved value
takes effect when the next stream starts, so an active stream never changes wire
formats without matching START/END boundaries. The next stream omits
controller-speaker audio and sends authored actuator samples through the best
negotiated fallback (`0x550A`, authored IR, or legacy rumble). Configurations
created before this option existed keep the enabled default. The
controller-audio path is output-only; it does not carry a
headset or microphone uplink.

At the current 144-frame packet size, one active controller produces about
333 controller-audio packets per second. The four-channel S16LE payload is
384,000 bytes/s; the 28-byte encrypted-control wire header adds about 9,333
bytes/s before transport encryption overhead. Sunshine keeps the maximum
1,920-byte PCM block out of the global feedback union and uses one combined
reference-counted allocation per accepted packet. The default remains enabled
because negotiation gates delivery to clients that explicitly advertise the
feature, while the toggle provides an actuator-only fallback on the next stream.

The encrypted, unreliable `0x550D` payload uses a 28-byte v1 wire header followed
by no more than 240 frames of 48 kHz S16LE samples in speaker-left,
speaker-right, actuator-left, actuator-right order. Flags are START (`1`), END
(`2`), and DISCONTINUITY (`4`); unknown flags and non-zero reserved bytes are
rejected. The sidecar emits 144-frame packets (3 ms at 48 kHz). The encrypted
packet is 1,204 bytes: within ENet's maximum but above its 900-byte default MTU,
so Sunshine explicitly requests unreliable fragmentation rather than allowing
ENet to promote fragments to reliable delivery. A bounded-queue drop marks the
next packet as discontinuous.

The bundled DualSense profile JSON files are adapted from HIDMaestro profiles.
See `HIDMAESTRO-LICENSE.txt` for the required MIT attribution.

The full USB composite profile is patched at runtime to use the same
Joystick application usage as the HID-only profile. Windows otherwise
misdecodes its idle Sony report as a held right trigger and an upward right
stick, causing repeated desktop navigation (issue #1056). This changes only
the top-level HID application usage; the USB audio interfaces, four-channel
stream, adaptive-trigger output and Sony report bytes remain unchanged. The
derived Genshin compatibility profile inherits this safe usage.
HID-only attaches actually serve the derived `dualsense-hidonly` profile:
its top-level collection usage is Joystick (0x04) instead of Game Pad
(0x05), because the root-enumerated device never gets the native DualSense
decoder and Windows' generic gamepad template reads the Sony byte layout as
a half-pressed right trigger plus a full-up right stick at rest, which
win32k turns into perpetual desktop navigation (issue #1056). As a
Joystick the device is only exposed through RawGameController/generic HID,
where every usage decodes correctly.
The optional Genshin compatibility attach flag derives a third profile from
`dualsense-composite` at runtime. It preserves the Sony VID/PID, descriptors,
and four-channel layout while changing only the USB product string from
`DualSense Wireless Controller` to the launch-model `Wireless Controller`.
The runtime profile starts the USB speaker control unmuted at its declared
maximum and commits the active endpoint's 4-channel, available-speaker and
full-range masks as quadraphonic (`0x33`) through Core Audio. This matches the
three settings applied by completing Windows' speaker setup wizard as required
by Genshin.
The sidecar advertises this support through a protocol capability bit so an
older runtime cannot silently accept an ineffective setting.
The v1 wire contract reserves capability bits and message numbers for the
virtual microphone. Normal startup intentionally does not advertise them;
only the explicit development prototype can enable those capabilities.

The Phase 2 composite-profile microphone path is development-only and requires
both the exact HIDMaestro 1.7.3.0 runtime and an explicit opt-in. Its elevated
attach/PCM/flush/destroy smoke test is:

```powershell
dotnet Sunshine.Ds5Sidecar.dll --self-test microphone-prototype
```

For an end-to-end developer check, `microphone-capture` snapshots the active
capture endpoints, creates the prototype, opens only its newly added endpoint
through WASAPI, streams a 440 Hz signal for five seconds, and requires observed
host streaming, zero submit errors, captured frames, and non-zero PCM before it
passes:

```powershell
dotnet Sunshine.Ds5Sidecar.dll --self-test microphone-capture
```

This temporary path also enumerates the composite profile's HID and render
interfaces; it is not the final capture-only virtual microphone product.
The composite session monitors every Windows default render and capture role.
If Windows selects a HIDMaestro-backed virtual DualSense endpoint as a default,
the helper reports the policy violation and exits; Sunshine then performs its
single recovery attach in HID-only DS5 mode. This read-only fail-closed guard
avoids undocumented audio-policy writes and never changes a user's defaults.

The trigger effects and lightbar of an output report a game writes to the
virtual pad are read the way the hardware reads them: only when the report's
validity byte for that field is set. A game leaves the fields it is not
programming zero, and reading those zeros as an instruction would cancel an
effect the game just armed and strobe a held color. A validity byte the decoder
does not expose governs nothing, so the fields it would gate are read
unconditionally. The motor bytes are read unconditionally as well, because their
zeros can cancel a rumble that is still playing while gating them can drop a
stop that has no other way to arrive.
