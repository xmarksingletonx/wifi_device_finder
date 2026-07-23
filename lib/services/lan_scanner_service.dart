import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../config.dart';

/// Finds newly-joined devices on the Wi-Fi LAN without root.
///
/// Android 10+ blocks app access to /proc/net/arp, so there is no
/// unprivileged way to read the ARP table (MAC addresses) on-device -
/// see https://issuetracker.google.com/issues/128554635. Instead this scans
/// by pinging every host on the subnet (Android's built-in ping binary has
/// raw-socket capability and works for any app, no root needed) and diffs
/// two scans: whatever IP responds after a device joins that didn't respond
/// before is the new device.
///
/// iOS allows neither raw ICMP (no entitlement) nor spawning a `ping`
/// process (no Process API at all) for third-party apps, so on iOS host
/// presence is instead inferred by racing short TCP connect attempts
/// against a handful of commonly-open ports - a live host either accepts
/// the connection or refuses it (fast RST); a dark host just times out.
/// This is a best-effort heuristic (a host with all of these ports
/// firewalled will be missed) rather than the exhaustive ICMP sweep
/// Android gets, matching how non-jailbroken iOS LAN-scanner apps work.
class LanScannerService {
  LanScannerService._();
  static final instance = LanScannerService._();

  final _netInfo = NetworkInfo();

  /// Current Wi-Fi IPv4 address, or null if not on Wi-Fi / unavailable.
  Future<String?> currentWifiIp() => _netInfo.getWifiIP();

  /// Derives the /24 subnet prefix (e.g. "192.168.1.") from an IPv4 address.
  /// Assumes a /24 network, true for the vast majority of consumer/site
  /// routers and simplest to scan exhaustively in a few seconds.
  String? subnetPrefixFor(String? ip) {
    if (ip == null) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  /// Pings every host in [Config.firstHost]-[Config.lastHost] on [prefix]
  /// (e.g. "192.168.1.") and returns the set of IPs that responded.
  /// [onProgress] reports (hostsChecked, totalHosts) as the scan proceeds.
  Future<Set<String>> scanSubnet(
    String prefix, {
    void Function(int done, int total)? onProgress,
  }) async {
    final hosts = [
      for (var i = Config.firstHost; i <= Config.lastHost; i++) i,
    ];
    final found = <String>{};
    var done = 0;

    for (var i = 0; i < hosts.length; i += Config.scanConcurrency) {
      final batch = hosts.skip(i).take(Config.scanConcurrency);
      await Future.wait(batch.map((h) async {
        final ip = '$prefix$h';
        if (await _isHostAlive(ip)) found.add(ip);
        done++;
        onProgress?.call(done, hosts.length);
      }));
    }
    return found;
  }

  Future<bool> _isHostAlive(String ip) =>
      Platform.isIOS ? _probeTcp(ip) : _pingHost(ip);

  Future<bool> _pingHost(String ip) async {
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '${Config.pingTimeoutSeconds}', ip],
      ).timeout(Duration(seconds: Config.pingTimeoutSeconds + 2));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Tries each port in [Config.iosProbePorts] in turn. A successful connect
  /// means the port is open; a *fast* failure (well under the timeout)
  /// means the host actively refused the connection (RST) - either way the
  /// host is alive. A failure that takes the full timeout means nothing
  /// answered, so we move on to the next port before giving up on the host.
  Future<bool> _probeTcp(String ip) async {
    for (final port in Config.iosProbePorts) {
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(ip, port,
            timeout: Config.iosProbeTimeout);
        socket.destroy();
        return true;
      } catch (_) {
        if (stopwatch.elapsed < Config.iosProbeRefusalThreshold) return true;
      }
    }
    return false;
  }
}
