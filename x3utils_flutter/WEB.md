# x3utils — one Dart codebase, no OpenOCD

x3utils talks to the ST-Link **directly in Dart**. OpenOCD is gone entirely: no
bundled `openocd` binary, no `.cfg` scripts, no PowerShell/`.sh` RDP toolkit, no
child processes, and no JavaScript bridge. The ST-Link protocol, Cortex-M debug
control, and the AT32F415 / STM32F1 flash algorithms are pure Dart, ported from
the openocd-ts project.

The only platform-specific piece is the USB transport:

- **Web** — WebUSB via `dart:js_interop` (`lib/stlink/transport_web.dart`).
- **Desktop (Win/macOS/Linux)** — libusb-1.0 via direct `dart:ffi`
  (`lib/stlink/transport_native.dart`); no third-party USB package.

Selected by a conditional import (`transport_open.dart`), so the same app runs
in the browser and as a native desktop app off one codebase.

## Layout

```
lib/stlink/            pure-Dart ST-Link stack (no platform code)
  transport.dart         UsbTransport interface
  transport_web.dart     WebUSB (js_interop)
  transport_native.dart  libusb-1.0 (dart:ffi)
  transport_open.dart    conditional selector
  stlink.dart            ST-Link APIv2 protocol
  cortexm.dart           halt/run/step/reset, FPU detect
  loader.dart            Thumb SRAM flash loaders (halfword + word)
  flash.dart             AT32 (FMC) + STM32F1 (FPEC) drivers + FAP/RDP
  targets.dart           DBGMCU IDCODE / PID detection
  session.dart           high-level connect/dump/erase/write/verify/rescue
lib/engine/
  openocd_runner.dart    thin adapter: AppController's flash API over the session
  rdp_runner.dart        Check / Rescue over the session's FAP support
  io/                    web VFS + dart:io shim (see below)
```

`openocd_runner.dart` / `rdp_runner.dart` keep their names and public API so
`AppController` is unchanged, but they are now thin wrappers over
`StlinkSession` — no command strings, no output parsing.

## Web storage & files

The desktop app is file-centric; the browser has no filesystem, so
`lib/engine/io/` provides a `dart:io` shim (`File`/`Directory`/`Platform`) over
an in-memory VFS that:

- persists every write to **IndexedDB** (via `package:web`) — loaded before
  `runApp` (see `lib/web_boot.dart`), so nothing is lost across reloads;
- **downloads** any `.bin`/`.zip` artifact as it's saved, so backups also land
  in the browser's Downloads.

The default entry (`lib/main.dart`) is web-aware via `web_boot.dart` (a
conditional import): on web it loads the VFS and overlays the "Saved files"
button; on native it's a no-op, so there's a single entry point for every
platform. Native builds use the real `dart:io` (the shim is web-only).

## Build & run

```sh
flutter run   -d chrome                            # web (dev)
flutter build web                                  # web (prod → build/web, serve over HTTPS/localhost)

flutter run                                        # native desktop
flutter build windows | macos | linux             # native desktop
```

Tip: Flutter web caches aggressively via a service worker — after a rebuild,
hard-refresh (Ctrl/Cmd+Shift+R) if you don't see the latest UI.

## Requirements & caveats

- **Web:** Chrome/Edge (WebUSB); HTTPS or localhost. First connect needs a click
  (WebUSB `requestDevice` gesture); after granting once, reconnects are silent.
- **Desktop:** libusb-1.0 must be present at runtime (Linux `libusb-1.0-0`;
  macOS `brew install libusb`; Windows: bundle `libusb-1.0.dll` beside the exe).
  The ST-Link must use WinUSB on Windows (official ST driver or Zadig).
- **Endpoints:** the native transport targets ST-Link/V2-class probes
  (interface 0, bulk EP 0x01/0x81) — the common scooter probe. V2-1/V3 layouts
  may need config-descriptor parsing.
- **Not yet hardware-tested through either transport from this Dart code.** It
  builds clean (`flutter analyze`: no issues; `flutter build web`: ok) and the
  register/flash logic is a faithful port of the hardware-confirmed openocd-ts
  stack, but the browser↔WebUSB and desktop↔libusb round trips need a live run.
```
