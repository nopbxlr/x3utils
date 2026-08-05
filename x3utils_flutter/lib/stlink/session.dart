// ST-Link session — a thin adapter over the published `swdart` package
// (https://github.com/nopbxlr/swdart), which is the extracted, standalone
// version of the pure-Dart ST-Link/SWD stack that used to live in this folder.
//
// This keeps the exact StlinkSession / ConnMode surface the engine runners
// expect, so nothing else in the app changes — the flashing/RDP behaviour is
// identical, it's just backed by the shared library instead of an embedded copy.
import 'dart:typed_data';

import 'package:swdart/swdart.dart';

// Re-export the types callers used to get from this file (via swdart now).
export 'package:swdart/swdart.dart' show ProtectionState, ProtectionResult, TargetInfo;

/// Connection strategies in x3utils' own vocabulary, mapped onto swdart's
/// generic [ConnectMode]:
/// - [defaultSwd]  → plain SWD attach
/// - [cloneC45]    → held reset + guided "C45 → GND" manual step (waits for
///   [sendContinue])
/// - [genuineC45]  → hardware nRST under-reset attach
/// - [powerRace]   → hammer the attach until the power-on window is caught
enum ConnMode { defaultSwd, cloneC45, genuineC45, powerRace }

ConnectMode _toConnectMode(ConnMode m) => switch (m) {
  ConnMode.defaultSwd => ConnectMode.normal,
  ConnMode.genuineC45 => ConnectMode.underReset,
  ConnMode.cloneC45 => ConnectMode.guided,
  ConnMode.powerRace => ConnectMode.attachRace,
};

/// Default flash window (AT32F415: 128 KB from the flash base) — preserved so
/// the no-argument dump/erase behave exactly as before.
const int flashBase = 0x08000000;
const int fullLen = 0x20000;

/// Backwards-compatible facade over swdart's [Probe]. A single shared instance
/// is reused across the app's runners, exactly as the old session was.
class StlinkSession {
  StlinkSession._();
  static final StlinkSession shared = StlinkSession._();

  final Probe _probe = Probe();

  bool get isConnected => _probe.isConnected;

  void onLog(void Function(String line) cb) => _probe.onLog(cb);

  Future<TargetInfo> connect(ConnMode mode) => _probe.connect(_toConnectMode(mode));

  Future<TargetInfo> connectRace() => _probe.connect(ConnectMode.attachRace);

  /// Release a guided ([ConnMode.cloneC45]) connect. False if none is waiting.
  bool sendContinue() => _probe.continueConnect();

  /// Abort an in-progress power-race.
  void stop() => _probe.abort();

  Future<Uint8List> dumpImage([int address = flashBase, int length = fullLen]) =>
      _probe.readFlash(address: address, length: length);

  Future<void> eraseAddress([int address = flashBase, int length = fullLen]) =>
      _probe.erase(address, length);

  Future<void> eraseAll() => _probe.eraseAll();

  Future<void> writeBank(Uint8List bytes, [int address = flashBase]) =>
      _probe.writeFlash(address, bytes);

  Future<void> verifyImage(Uint8List bytes, [int address = flashBase]) =>
      _probe.verifyFlash(address, bytes);

  Future<ProtectionState> readProtection() => _probe.readProtection();

  Future<ProtectionResult> disableProtection() => _probe.setProtection(false);

  Future<ProtectionResult> enableProtection() => _probe.setProtection(true);

  Future<void> resetHalt() => _probe.resetHalt();

  Future<void> resetRun() => _probe.resetRun();

  Future<void> disconnect() => _probe.disconnect();
}
