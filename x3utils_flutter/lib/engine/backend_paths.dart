// Vestigial: the app talks to the ST-Link directly (WebUSB/libusb). The
// backend (WebUSB / libusb) is built in. Kept as a no-op so the existing
// construction sites compile unchanged.
class BackendPaths {
  const BackendPaths([this.exe = '', this.scripts = '']);
  final String exe;
  final String scripts;
  String get binDir => '';
  static BackendPaths find() => const BackendPaths();
}

class BackendUnavailable implements Exception {
  const BackendUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
