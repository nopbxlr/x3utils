// Flash/debug runner. One platform-agnostic implementation over the pure-Dart
// ST-Link session (lib/stlink/), whose USB transport is WebUSB on web and
// libusb on desktop. No external process, no bundled binaries, no text protocol.
//
// The class + result/evidence types keep their historical names so AppController
// is unchanged; "args" are now compact internal op tokens, internal tokens.
import '../models.dart' show ConnectionMode;
import '../stlink/session.dart';
import 'io/io.dart';
import 'backend_paths.dart';

/// Per-attempt classification of a power-race respawn miss.
enum RaceTier { searching, noisy, nearCatch, adapterGone, timedOut }

class FlashResult {
  const FlashResult(this.exitCode, this.evidence);
  final int exitCode;
  final FlashEvidence evidence;
  bool get ok => exitCode == 0;
}

/// What a run proved. Set directly by the runner (no log-scraping needed), but
/// [record] is kept so any surfaced line still contributes.
class FlashEvidence {
  bool caught = false;
  bool dumped = false;
  bool erased = false;
  bool wrote = false;
  bool verified = false;

  void record(String line) {
    final low = line.toLowerCase();
    caught |= low.contains('target halted') || low.contains('caught; hold power');
    dumped |= _dumped.hasMatch(low);
    erased |= _erased.hasMatch(low);
    wrote |= _hasWrite(low);
    verified |= _verified.hasMatch(low);
  }
}

final _dumped = RegExp(r'\bdumped\b');
final _erased = RegExp(r'\berased\b');
final _write = RegExp(r'\b(wrote|written)\b');
final _verified = RegExp(r'\bverified\b');

bool _hasWrite(String low) => _write.hasMatch(low);

/// True once a line proves the run got past connect (drives the progress UI).
bool hasTargetProgressEvidence(String low) =>
    low.contains('target halted') ||
    low.contains('caught; hold power') ||
    low.contains('ready to flash') ||
    _dumped.hasMatch(low) ||
    _erased.hasMatch(low) ||
    _hasWrite(low) ||
    _verified.hasMatch(low);

class FlashRunner {
  FlashRunner([this.paths]);
  final BackendPaths? paths;

  final StlinkSession _session = StlinkSession.shared;

  // ── op-token builders (mode, path) — no external command strings ──────
  List<String> checkArgs(ConnectionMode mode, int countdown) => ['check', '${mode.index}'];
  List<String> dumpArgs(ConnectionMode mode, int countdown, String path) =>
      ['dump', '${mode.index}', path];
  List<String> flashArgs(ConnectionMode mode, int countdown, String path) =>
      ['flash', '${mode.index}', path];
  List<String> flashSlot0Args(ConnectionMode mode, int countdown, String path) =>
      ['slot0', '${mode.index}', path];

  bool sendContinue() => _session.sendContinue();
  void kill() => _session.stop();

  ConnMode _mode(ConnectionMode m) => switch (m) {
    ConnectionMode.defaultSwd => ConnMode.defaultSwd,
    ConnectionMode.cloneC45 => ConnMode.cloneC45,
    ConnectionMode.genuineC45 => ConnMode.genuineC45,
    ConnectionMode.powerRace => ConnMode.powerRace,
  };

  Future<void> _ensureConnected(ConnectionMode mode, void Function(String) onLine) async {
    if (_session.isConnected) return;
    await _session.connect(_mode(mode));
    onLine('target halted');
  }

  Future<void> _execVerb(String verb, String path, FlashEvidence ev) async {
    switch (verb) {
      case 'check':
        break;
      case 'dump':
        final bytes = await _session.dumpImage();
        File(path).writeAsBytesSync(bytes);
        ev.dumped = true;
      case 'flash':
        final bytes = File(path).readAsBytesSync();
        await _session.eraseAddress();
        ev.erased = true;
        await _session.writeBank(bytes);
        ev.wrote = true;
        await _session.verifyImage(bytes);
        ev.verified = true;
      case 'slot0':
        final bytes = File(path).readAsBytesSync();
        await _session.eraseAddress(0x08001000, bytes.length);
        ev.erased = true;
        await _session.writeBank(bytes, 0x08001000);
        ev.wrote = true;
        await _session.verifyImage(bytes, 0x08001000);
        ev.verified = true;
    }
  }

  Future<FlashResult> run(List<String> args, void Function(String line) onLine) async {
    _session.onLog(onLine);
    final ev = FlashEvidence();
    final verb = args[0];
    final mode = ConnectionMode.values[int.parse(args[1])];
    final path = args.length > 2 ? args[2] : '';
    try {
      await _ensureConnected(mode, onLine);
      ev.caught = true;
      await _execVerb(verb, path, ev);
      return FlashResult(0, ev);
    } catch (e) {
      onLine('[error] $e');
      await _recover(); // drop the (possibly wedged) probe so a retry reconnects
      return FlashResult(1, ev);
    }
  }

  /// After a failure the ST-Link/target link can be in a bad state (e.g. a
  /// mid-command reset), and libusb then fails every transfer on the reused
  /// handle. Tear the connection down so the next attempt re-opens the probe
  /// and re-inits it from scratch.
  Future<void> _recover() async {
    try {
      await _session.disconnect();
    } catch (_) {}
  }

  Future<FlashResult> runRace(
    List<String> args, {
    required void Function(String line) onLine,
    required void Function(int attempt, RaceTier tier) onAttempt,
    void Function()? onCaught,
  }) async {
    _session.onLog(onLine);
    final ev = FlashEvidence();
    final verb = args[0];
    final path = args.length > 2 ? args[2] : '';
    try {
      onAttempt(1, RaceTier.searching);
      onLine('power-race: apply power now — hammering connects');
      await _session.connectRace();
      ev.caught = true;
      onCaught?.call();
      onLine('caught; hold power');
      onLine('target halted');
      await _execVerb(verb, path, ev);
      return FlashResult(0, ev);
    } catch (e) {
      onLine('[race] $e');
      await _recover();
      return FlashResult(-1, ev);
    }
  }
}
