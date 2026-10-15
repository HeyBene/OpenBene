import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const OpenBeneApp());

class OpenBeneApp extends StatelessWidget {
  const OpenBeneApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OpenBene 锚点导航',
        theme: ThemeData(colorSchemeSeed: const Color(0xff167d8d)),
        home: const NavigationEntry(),
      );
}

/// Native ARCore owns the camera, saved routes and BLE lifecycle together.
class NavigationEntry extends StatefulWidget {
  const NavigationEntry({super.key});
  @override
  State<NavigationEntry> createState() => _NavigationEntryState();
}

class _NavigationEntryState extends State<NavigationEntry> {
  static const _channel = MethodChannel('com.openbene/navigation');
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() { _opening = true; _error = null; });
    try {
      await _channel.invokeMethod<void>('openNavigation');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '导航启动失败');
    } on MissingPluginException {
      if (mounted) setState(() => _error = '请在 Android 手机上运行此工程。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OpenBene 锚点导航')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('采集起点和节点 · 本地保存航线 · 蓝牙驱动底盘',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _opening ? null : _open,
                  child: Text(_opening ? '正在打开…' : '打开锚点导航'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      );
}
