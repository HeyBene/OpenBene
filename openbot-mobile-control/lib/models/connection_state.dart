enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class ConnectionState {
  final ConnectionStatus status;
  final String? message;
  final DateTime timestamp;

  ConnectionState({
    required this.status,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ConnectionState copyWith({
    ConnectionStatus? status,
    String? message,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      message: message ?? this.message,
      timestamp: DateTime.now(),
    );
  }

  String get statusText {
    switch (status) {
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case ConnectionStatus.error:
        return 'Error';
    }
  }
}
