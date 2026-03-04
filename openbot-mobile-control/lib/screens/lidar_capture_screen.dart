import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/lidar_capture_service.dart';

class LidarCaptureScreen extends StatefulWidget {
  const LidarCaptureScreen({super.key});

  @override
  State<LidarCaptureScreen> createState() => _LidarCaptureScreenState();
}

class _LidarCaptureScreenState extends State<LidarCaptureScreen> {
  final LidarCaptureFlutterService _lidarService = LidarCaptureFlutterService();
  
  int _fps = 10;
  bool _includeDepth = true;
  String _datasetName = '';
  List<DatasetInfo> _datasets = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _lidarService.initialize();
    await _loadDatasets();
  }

  Future<void> _loadDatasets() async {
    final datasets = await _lidarService.listDatasets();
    if (mounted) {
      setState(() {
        _datasets = datasets;
      });
    }
  }

  Future<void> _startCapture() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _lidarService.startCapture(
      datasetName: _datasetName.isNotEmpty ? _datasetName : null,
      fps: _fps,
      includeDepth: _includeDepth,
    );

    if (!success) {
      setState(() {
        _errorMessage = 'Failed to start capture';
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _stopCapture() async {
    setState(() {
      _isLoading = true;
    });

    final result = await _lidarService.stopCapture();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
      await _loadDatasets();
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportZip(DatasetInfo dataset) async {
    final path = await _lidarService.exportZip(dataset.id);
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to: $path')),
      );
    }
  }

  Future<void> _deleteDataset(DatasetInfo dataset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Dataset'),
        content: Text('Are you sure you want to delete "${dataset.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _lidarService.deleteDataset(dataset.id);
      await _loadDatasets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _lidarService,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LiDAR Capture'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        body: Consumer<LidarCaptureFlutterService>(
          builder: (context, service, child) {
            final status = service.status;
            final isCapturing = status?.isCapturing ?? false;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  _buildStatusCard(status),
                  const SizedBox(height: 16),

                  // Capture Controls
                  if (!isCapturing) ...[
                    _buildCaptureControls(),
                    const SizedBox(height: 16),
                  ],

                  // Start/Stop Button
                  _buildCaptureButton(isCapturing),
                  const SizedBox(height: 24),

                  // Datasets List
                  _buildDatasetsSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusCard(CaptureStatus? status) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status?.isCapturing == true ? Icons.videocam : Icons.videocam_off,
                  color: status?.isCapturing == true ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  status?.isCapturing == true ? 'Capturing' : 'Idle',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (status != null) ...[
              _buildStatusRow('Frames', '${status.frameCount}'),
              _buildStatusRow('Tracking', status.trackingState),
              _buildStatusRow('LiDAR', status.lidarSupported ? 'Supported' : 'Not Available'),
              if (status.datasetName != null)
                _buildStatusRow('Dataset', status.datasetName!),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureControls() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capture Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // Dataset Name
            TextField(
              decoration: const InputDecoration(
                labelText: 'Dataset Name (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _datasetName = value,
            ),
            const SizedBox(height: 16),

            // FPS Slider
            Row(
              children: [
                const Text('FPS: '),
                Expanded(
                  child: Slider(
                    value: _fps.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: _fps.toString(),
                    onChanged: (value) {
                      setState(() {
                        _fps = value.round();
                      });
                    },
                  ),
                ),
                Text(_fps.toString()),
              ],
            ),
            const SizedBox(height: 8),

            // Include Depth Toggle
            SwitchListTile(
              title: const Text('Include Depth'),
              subtitle: Text(
                _lidarService.isLidarSupported
                    ? 'Capture LiDAR depth data'
                    : 'LiDAR not available on this device',
              ),
              value: _includeDepth,
              onChanged: _lidarService.isLidarSupported
                  ? (value) {
                      setState(() {
                        _includeDepth = value;
                      });
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButton(bool isCapturing) {
    return ElevatedButton.icon(
      onPressed: _isLoading
          ? null
          : isCapturing
              ? _stopCapture
              : _startCapture,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(isCapturing ? Icons.stop : Icons.play_arrow),
      label: Text(
        _isLoading
            ? 'Please wait...'
            : isCapturing
                ? 'Stop Capture'
                : 'Start Capture',
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: isCapturing ? Colors.red : Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildDatasetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Datasets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDatasets,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_datasets.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No datasets saved yet.'),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _datasets.length,
            itemBuilder: (context, index) {
              final dataset = _datasets[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    dataset.hasDepth ? Icons.layers : Icons.image,
                    color: Colors.blue,
                  ),
                  title: Text(dataset.name),
                  subtitle: Text(
                    '${dataset.frameCount} frames • ${_formatSize(dataset.sizeBytes)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'export') {
                        _exportZip(dataset);
                      } else if (value == 'delete') {
                        _deleteDataset(dataset);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'export',
                        child: Row(
                          children: [
                            Icon(Icons.archive),
                            SizedBox(width: 8),
                            Text('Export ZIP'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _lidarService.disposeService();
    super.dispose();
  }
}