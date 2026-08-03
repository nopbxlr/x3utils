# Native desktop: libusb setup

The desktop builds talk to the ST-Link over **libusb-1.0** (via `dart:ffi`, in
`lib/stlink/transport_native.dart`). The **web build does not need libusb** — it
uses WebUSB.

The loader (`_Libusb.open`) searches, in order: the app's own directory, then
common system/Homebrew locations. Because Flutter places bundled libraries next
to the executable for **both** `flutter run` (debug) **and** `flutter build`
(release), a bundled libusb is found the same way in either mode.

Two ways to make it available:

## Windows

**Included** — `windows/libusb-1.0.dll` is committed, so the Windows build works
out of the box. `windows/CMakeLists.txt` bundles it next to the app on every
build (debug + release); `DynamicLibrary` finds a DLL beside the `.exe`.

Provenance (replace with a newer release the same way):

- Source: official libusb **v1.0.30** release
  (`github.com/libusb/libusb/releases`), the **MinGW64** x64 build.
- Verified: GPG "Good signature from Tormod Volden" against the libusb repo's
  `KEYS`; machine type `0x8664` (x64); imports only `KERNEL32.dll` + `msvcrt.dll`
  (self-contained — no VC++ redistributable needed).
- `windows/libusb-1.0.dll` sha256:
  `5bd409849825009b6fe25861a6147f76d256aab248f07049d78387e3bff12d94`
- License: LGPL-2.1 — see `windows/libusb-1.0-LICENSE.txt`.

The ST-Link must be bound to **WinUSB** — install ST's STSW-LINK009 driver, or
use [Zadig](https://zadig.akeo.ie/) to put WinUSB on the "STM32 STLink"
interface. (Same requirement as any libusb tool.)

## Linux

Easiest: install system libusb — it's already on the loader's search path for
debug and release:

```sh
sudo apt install libusb-1.0-0        # Debian/Ubuntu
sudo dnf install libusb1             # Fedora
```

Or bundle it: drop `libusb-1.0.so.0` at **`linux/libusb-1.0.so.0`** and
`linux/CMakeLists.txt` installs it into the app's `lib/` (on the `$ORIGIN/lib`
RPATH) for both build modes.

Give your user access to the probe (udev rule), e.g.:

```
# /etc/udev/rules.d/49-stlink.rules
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", MODE="0666"
```

## macOS

Install libusb with Homebrew — the loader searches `/opt/homebrew/lib` (Apple
Silicon) and `/usr/local/lib` (Intel), so it works in debug and release:

```sh
brew install libusb
```

To ship a self-contained `.app` that doesn't require Homebrew, copy
`libusb-1.0.0.dylib` into `YourApp.app/Contents/Frameworks/` via an Xcode
"Copy Files" build phase and code-sign it — the loader already looks in
`../Frameworks` relative to the executable. (Not wired up here to avoid touching
the signed macOS project; add it when you set up distribution.)

## Notes

- USB PID → endpoint: the transport handles ST-Link/V2 (incl. clones, PID
  `0x3748`, bulk OUT `0x02`) and V2-1/V3 (OUT `0x01`); interface 0, IN `0x81`.
- If a probe isn't found, the thrown error names exactly where to place libusb.
