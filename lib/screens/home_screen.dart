import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lan_scanner_service.dart';

/// Field flow for finding the IP a router just handed to a newly-joined
/// device (e.g. a SenseCAP M2 gateway during Wi-Fi onboarding):
///  1. Join the site Wi-Fi (this app just deep-links to Android's Wi-Fi
///     settings - it doesn't join networks programmatically).
///  2. Scan the subnet to record which hosts already respond (baseline).
///  3. Go complete the new device's own Wi-Fi setup (outside this app -
///     vendor-specific), then scan again.
///  4. Whatever IP responds now but didn't before is the new device.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _svc = LanScannerService.instance;

  bool _permissionDenied = false;
  String? _localIp;
  String? _prefix;

  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;

  Set<String>? _baseline;
  Set<String>? _newIps;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndNetwork();
  }

  Future<void> _checkPermissionAndNetwork() async {
    // Android ties Wi-Fi IP/SSID lookups to location permission (Android 10+).
    final status = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    setState(() => _permissionDenied = !status.isGranted);
    if (status.isGranted) await _refreshNetworkInfo();
  }

  Future<void> _refreshNetworkInfo() async {
    final ip = await _svc.currentWifiIp();
    if (!mounted) return;
    setState(() {
      _localIp = ip;
      _prefix = _svc.subnetPrefixFor(ip);
    });
  }

  Future<void> _scanBaseline() async {
    final prefix = _prefix;
    if (prefix == null || _scanning) return;
    setState(() {
      _scanning = true;
      _scanDone = 0;
      _scanTotal = 254;
      _baseline = null;
      _newIps = null;
    });
    final result = await _svc.scanSubnet(
      prefix,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _scanDone = done;
          _scanTotal = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _baseline = result;
      _scanning = false;
    });
  }

  Future<void> _scanAgain() async {
    final prefix = _prefix;
    final baseline = _baseline;
    if (prefix == null || baseline == null || _scanning) return;
    setState(() {
      _scanning = true;
      _scanDone = 0;
      _scanTotal = 254;
      _newIps = null;
    });
    final result = await _svc.scanSubnet(
      prefix,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _scanDone = done;
          _scanTotal = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _newIps = result.difference(baseline);
      _scanning = false;
    });
  }

  void _reset() {
    setState(() {
      _baseline = null;
      _newIps = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Device Finder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildNetworkCard(),
          const SizedBox(height: 12),
          _buildBaselineCard(),
          if (_baseline != null) ...[
            const SizedBox(height: 12),
            _buildScanAgainCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STEP 1 · JOIN THE SITE WI-FI',
                style: TextStyle(fontSize: 12, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            if (_permissionDenied)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Location permission is required to read the Wi-Fi '
                      'network (Android restriction). Grant it, then '
                      'return here.'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: openAppSettings,
                    child: const Text('Open App Permissions'),
                  ),
                ],
              )
            else
              Text(_localIp == null
                  ? 'Not connected to a Wi-Fi network yet.'
                  : 'Connected: $_localIp  (scanning ${_prefix}1-254)'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        AppSettings.openAppSettings(type: AppSettingsType.wifi),
                    child: const Text('Open Wi-Fi Settings'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _checkPermissionAndNetwork,
                    child: const Text('Refresh'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBaselineCard() {
    final canScan = _prefix != null && !_scanning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STEP 2 · SCAN BASELINE',
                style: TextStyle(fontSize: 12, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            const Text('Scan the network before connecting the new device '
                '(e.g. SenseCAP M2) so we know what\'s already there.'),
            const SizedBox(height: 12),
            if (_scanning && _baseline == null) _buildProgress(),
            if (_baseline != null)
              Text('${_baseline!.length} device(s) already on the network.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canScan ? _scanBaseline : null,
              child: Text(_baseline == null ? 'Scan Baseline' : 'Rescan Baseline'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanAgainCard() {
    final canScan = _prefix != null && !_scanning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STEP 3 · CONNECT DEVICE, THEN SCAN AGAIN',
                style: TextStyle(fontSize: 12, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            const Text('Now put the new device into Wi-Fi setup mode and '
                'join it to this network (its own app/console), then tap '
                'Scan Again.'),
            const SizedBox(height: 12),
            if (_scanning && _baseline != null) _buildProgress(),
            if (_newIps != null) _buildResults(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: canScan ? _scanAgain : null,
                    child: const Text('Scan Again'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final total = _scanTotal == 0 ? 1 : _scanTotal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _scanDone / total),
          const SizedBox(height: 4),
          Text('Scanning... $_scanDone / $_scanTotal'),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final newIps = _newIps!;
    if (newIps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('No new devices yet - wait a few seconds for the DHCP '
            'lease and tap Scan Again.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('New device(s) found:'),
        const SizedBox(height: 4),
        ...newIps.map((ip) => Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                title: Text(ip),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy IP',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ip));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied $ip')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_browser),
                      tooltip: 'Open console',
                      onPressed: () => launchUrl(
                        Uri.parse('http://$ip'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
