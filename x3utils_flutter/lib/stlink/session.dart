// High-level ST-Link session (ported from openocd-ts src/bridge.ts). Drives the
// pure-Dart stack over a platform USB transport. Exposes the semantic operations
// the app needs — connect / dump / erase / write / verify / protection — plus the
// guided-C45 gate and power-race respawn.
import 'dart:async';
import 'dart:typed_data';

import 'cortexm.dart';
import 'flash.dart';
import 'stlink.dart';
import 'targets.dart';
import 'transport.dart';
import 'transport_open.dart';
import 'util.dart';

enum ConnMode { defaultSwd, cloneC45, genuineC45, powerRace }

const flashBase = 0x08000000;
const slot0Base = 0x08001000;
const fullLen = 0x20000; // 128 KB

class StlinkSession {
  StlinkSession();

  /// Shared session — there is one physical probe, so the flash and RDP runners
  /// use the same connection rather than fighting over the USB device.
  static final StlinkSession shared = StlinkSession();

  bool get isConnected => _probe != null;

  UsbTransport? _usb;
  Stlink? _probe;
  CortexM? _core;
  TargetInfo? _target;
  FlashDriver? _driver;

  void Function(String line)? _log;
  Completer<void>? _continueGate;
  bool _stop = false;

  TargetInfo? get target => _target;
  String get probeName => _probe?.probeName ?? '?';
  bool get hasMem16 => _probe?.hasMem16 ?? false;

  void onLog(void Function(String) cb) => _log = cb;
  void _emit(String line) => _log?.call(line);

  /// Release the guided-C45 gate ("Continue" after grounding C45).
  bool sendContinue() {
    final g = _continueGate;
    if (g != null && !g.isCompleted) {
      _continueGate = null;
      g.complete();
      return true;
    }
    return false;
  }

  void stop() => _stop = true;

  Future<void> _openProbe() async {
    if (_probe != null) return;
    _usb = await reacquireStlink() ?? await requestStlink();
    final p = Stlink(_usb!);
    await p.init();
    _probe = p;
    _emit('[probe] ${p.probeName} (${p.version.text})${p.hasMem16 ? ", 16-bit" : ""}');
  }

  FlashDriver _makeDriver() {
    final t = _target!;
    if (t.family == 'AT32') return At32Flash(_probe!, _core!, t.pageSize, t.sramBytes);
    if (t.family == 'STM32F1') return Stm32f1Flash(_probe!, _core!, t.pageSize, t.sramBytes);
    throw StlinkException('unsupported target family: ${t.family}');
  }

  Future<TargetInfo> connect(ConnMode mode) async {
    if (mode == ConnMode.powerRace) return connectRace();
    await _openProbe();
    final p = _probe!;
    final underReset = mode == ConnMode.cloneC45 || mode == ConnMode.genuineC45;

    if (underReset) {
      _emit('[connect] ${mode.name}: asserting nRST');
      await p.driveNrst(0);
      if (mode == ConnMode.cloneC45) {
        _emit('== touch C45 to GND now, then press Continue ==');
        await _waitContinue();
      }
    }
    await p.enterSwd();
    final idcode = await p.readIdcode();
    _emit('[connect] SWD IDCODE ${hex(idcode)}');

    _core = CortexM(p);
    if (underReset) {
      await _core!.halt();
      await p.writeDebugReg(demcr, 1); // VC_CORERESET
      await p.driveNrst(1);
      await _core!.waitHalted();
      await p.writeDebugReg(demcr, 0);
      _emit('[connect] core halted at reset vector');
    }
    return _finishAttach(idcode);
  }

  Future<TargetInfo> connectRace() async {
    await _openProbe();
    final p = _probe!;
    _stop = false;
    var attempt = 0;
    for (;;) {
      if (_stop) throw StlinkException('power-race stopped');
      attempt++;
      try {
        await p.enterSwd();
        final idcode = await p.readIdcode();
        if (idcode == 0) throw StlinkException('idcode 0');
        _emit('== caught on attempt $attempt; hold power ==');
        _core = CortexM(p);
        await _core!.halt();
        await _core!.waitHalted(1500);
        return _finishAttach(idcode);
      } catch (_) {
        if (attempt % 20 == 0) _emit('[race] $attempt attempts…');
        await sleep(5);
      }
    }
  }

  Future<TargetInfo> _finishAttach(int idcode) async {
    final p = _probe!;
    await _freezeWatchdogs(p);
    _target = await detectTarget(p, _core!);
    _driver = _target!.family == 'unknown' ? null : _makeDriver();
    _emit('[target] ${_target!.name}');
    final voltage = await p.getTargetVoltage().catchError((_) => null);
    if (voltage != null) _emit('[target] Vtarget ${voltage.toStringAsFixed(2)} V');
    return _target!;
  }

  /// Freeze the independent + window watchdogs (and low-power modes) while the
  /// core is halted, so a running IWDG/WWDG from the target's own firmware can't
  /// reset the chip mid-flash. Mirrors OpenOCD's `mmw 0xE0042004 0x00000307 0`
  /// (DBG_WWDG_STOP | DBG_IWDG_STOP | DBG_STANDBY | DBG_STOP | DBG_SLEEP). The
  /// DBGMCU/DEBUG control register (0xE0042004, bit layout shared by STM32F1 and
  /// AT32) is not reset by system reset, so setting it once on attach persists.
  Future<void> _freezeWatchdogs(Stlink p) async {
    const dbgmcuCr = 0xe0042004;
    try {
      final cur = await p.readDebugReg(dbgmcuCr);
      await p.writeDebugReg(dbgmcuCr, cur | 0x307);
      _emit('[debug] watchdogs frozen while halted (DBGMCU_CR |= 0x307)');
    } catch (_) {
      // Non-fatal: some parts may gate DBGMCU behind a clock; flashing may still
      // work if no watchdog is running.
    }
  }

  Future<void> _waitContinue() {
    final g = Completer<void>();
    _continueGate = g;
    return g.future;
  }

  FlashDriver get _drv {
    final d = _driver;
    if (_probe == null || _core == null) throw StlinkException('not connected');
    if (d == null) throw StlinkException('no flash driver for ${_target?.family}');
    return d;
  }

  Future<void> resetHalt() async {
    if (_core == null) throw StlinkException('not connected');
    await _core!.resetHalt();
    _emit('[target] reset halt');
  }

  Future<void> resetRun() async {
    if (_core == null) throw StlinkException('not connected');
    await _core!.resetRun();
    _emit('[target] reset, running');
  }

  Future<Uint8List> dumpImage([int address = flashBase, int length = fullLen]) async {
    if (_probe == null || _core == null) throw StlinkException('not connected');
    await _core!.halt();
    _emit('[dump] reading $length bytes from ${hex(address)}');
    final out = Uint8List(length);
    var done = 0;
    while (done < length) {
      final chunk = (length - done) < 4096 ? (length - done) : 4096;
      out.setRange(done, done + chunk, await _probe!.readMem32(address + done, chunk));
      done += chunk;
    }
    _emit('[dump] dumped $length bytes');
    return out;
  }

  Future<void> eraseAddress([int address = flashBase, int length = fullLen]) async {
    await _core!.resetHalt();
    _emit('[erase] ${hex(address)} +$length');
    await _drv.erase(address, length);
    _emit('[erase] erased');
  }

  Future<void> eraseAll() async {
    await _core!.resetHalt();
    _emit('[erase] mass erase');
    await _drv.massErase();
    _emit('[erase] erased');
  }

  Future<void> writeBank(Uint8List bytes, [int address = flashBase]) async {
    if (!await _core!.isHalted()) await _core!.halt();
    _emit('[write] ${bytes.length} bytes @ ${hex(address)}');
    await _drv.program(address, bytes);
    _emit('[write] wrote ${bytes.length} bytes');
  }

  Future<void> verifyImage(Uint8List bytes, [int address = flashBase]) async {
    if (!await _core!.isHalted()) await _core!.halt();
    _emit('[verify] ${bytes.length} bytes @ ${hex(address)}');
    await _drv.verify(address, bytes);
    _emit('[verify] verified');
  }

  Future<ProtectionState> readProtection() => _drv.readProtection();

  Future<ProtectionResult> disableProtection() async {
    await _core!.resetHalt();
    _emit('[rescue] clearing read protection (mass-erases flash)…');
    final res = await _drv.setProtection(false);
    _emit('[rescue] ${res.message}');
    return res;
  }

  Future<ProtectionResult> enableProtection() async {
    await _core!.resetHalt();
    final res = await _drv.setProtection(true);
    _emit('[protect] ${res.message}');
    return res;
  }

  Future<void> disconnect() async {
    _stop = true;
    try {
      await _probe?.close();
    } catch (_) {}
    _probe = null;
    _core = null;
    _driver = null;
    _target = null;
    _usb = null;
    _emit('[probe] disconnected');
  }
}
