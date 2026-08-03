// Read-protection toolkit (Check / Rescue), over the pure-Dart ST-Link session's
// FAP support. No external scripts or processes.
//
// Check exit codes match the historical contract: 0 = not protected,
// 2 = read-protected, 3 = inconclusive.
import '../models.dart';
import '../stlink/session.dart';
import 'backend_paths.dart';

class RdpRunner {
  RdpRunner([this.paths]);
  final BackendPaths? paths;

  final StlinkSession _session = StlinkSession.shared;

  bool get available => true;
  bool sendContinue() => _session.sendContinue();
  void kill() => _session.stop();

  ConnMode _mode(ConnectionMode m) => switch (m) {
    ConnectionMode.defaultSwd => ConnMode.defaultSwd,
    ConnectionMode.cloneC45 => ConnMode.cloneC45,
    ConnectionMode.genuineC45 => ConnMode.genuineC45,
    ConnectionMode.powerRace => ConnMode.powerRace,
  };

  Future<int> run(
    String verb,
    ConnectionMode mode,
    int timeout, {
    bool yes = false,
    required void Function(String) onLine,
    void Function(String chunk)? onChunk,
  }) async {
    _session.onLog(onLine);
    try {
      if (!_session.isConnected) {
        onLine('> rdp $verb (${mode.name})');
        await _session.connect(_mode(mode));
      }

      if (verb == 'Rescue') {
        final r = await _session.disableProtection();
        onLine(r.message);
        return 0;
      }

      final state = await _session.readProtection();
      if (state.enabled) {
        onLine('PROTECTED · ${state.level} — flash is read-locked.');
        return 2;
      }
      onLine('NOT PROTECTED — flash is readable.');
      return 0;
    } catch (e) {
      onLine('[rdp] error: $e');
      return 3;
    }
  }
}
