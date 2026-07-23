/// Tunable values in one place.
class Config {
  /// Host range scanned on the detected /24 subnet (x.x.x.1 - x.x.x.254).
  static const firstHost = 1;
  static const lastHost = 254;

  /// How many hosts to ping concurrently. Higher = faster scan, more load.
  static const scanConcurrency = 24;

  /// Per-host ping timeout. Android's ping binary takes this in whole seconds.
  static const pingTimeoutSeconds = 1;

  /// iOS-only: ports tried (in order) when TCP-probing for host presence,
  /// since iOS allows neither raw ping nor spawning a ping process.
  static const iosProbePorts = [80, 443, 22];

  /// iOS-only: how long to wait for a connect attempt on one port.
  static const iosProbeTimeout = Duration(milliseconds: 400);

  /// iOS-only: a connect failure faster than this is treated as an active
  /// refusal (RST) - proof the host is alive - rather than a silent timeout.
  static const iosProbeRefusalThreshold = Duration(milliseconds: 150);
}
