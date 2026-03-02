import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/app_state.dart';

/// 蓝牙设备扫描底部弹窗
class BluetoothScanSheet extends StatefulWidget {
  final AppState appState;

  const BluetoothScanSheet({super.key, required this.appState});

  @override
  State<BluetoothScanSheet> createState() => _BluetoothScanSheetState();
}

class _BluetoothScanSheetState extends State<BluetoothScanSheet> {
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _listenScanningState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    widget.appState.bluetoothService.stopScan();
    super.dispose();
  }

  void _listenScanningState() {
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((value) {
      if (!mounted) return;
      setState(() => _isScanning = value);
    });
  }

  void _startScan() {
    _scanSubscription?.cancel();

    setState(() => _results.clear());

    _scanSubscription = widget.appState.bluetoothService
        .scanDevices(timeout: const Duration(seconds: 6))
        .listen((results) {
      if (!mounted) return;

      _results
        ..clear()
        ..addAll(results.where((result) {
          // 只显示有名字的设备，过滤掉 Unknown Device
          return result.device.platformName.isNotEmpty;
        }));

      // 优先显示 OpenBot 设备（ESP32 固件名称为 "OpenBot: XXX"），其余按信号强度排序
      _results.sort((a, b) {
        final aName = a.device.platformName.toLowerCase();
        final bName = b.device.platformName.toLowerCase();
        final knownNames = [
          'openbot',
          'hm-10',
          'hc-08',
          'bt05',
          'jdy',
          'ble',
        ];
        final aKnown = knownNames.any((n) => aName.contains(n));
        final bKnown = knownNames.any((n) => bName.contains(n));
        if (aKnown && !bKnown) return -1;
        if (!aKnown && bKnown) return 1;
        return b.rssi.compareTo(a.rssi);
      });
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth_searching_rounded,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Scan for OpenBot',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _startScan,
                    tooltip: 'Scan again',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  _isScanning
                      ? 'Scanning for BLE devices...'
                      : 'No devices found. Tap refresh to retry.',
                  style: TextStyle(color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    final name = result.device.platformName.isEmpty
                        ? 'Unknown Device'
                        : result.device.platformName;

                    return ListTile(
                      leading: Icon(
                        Icons.bluetooth_rounded,
                        color: Colors.blue.shade600,
                      ),
                      title: Text(name),
                      subtitle: Text(result.device.remoteId.str),
                      trailing: Text(
                        '${result.rssi} dBm',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        final ok =
                            await widget.appState.connectToRobotWithBluetooth(
                          result.device,
                        );
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Bluetooth connection failed. Retry?',
                              ),
                              backgroundColor: Colors.red.shade600,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
