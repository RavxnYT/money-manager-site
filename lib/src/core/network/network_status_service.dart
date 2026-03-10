import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkStatusService {
  NetworkStatusService._();

  static final NetworkStatusService instance = NetworkStatusService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;
  bool _isOnline = true;

  bool get isOnline => _isOnline;
  Stream<bool> get statusStream => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final initial = await _connectivity.checkConnectivity();
    _updateFromResults(initial);

    _subscription =
        _connectivity.onConnectivityChanged.listen(_updateFromResults);
  }

  void _updateFromResults(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (_isOnline == online) return;
    _isOnline = online;
    _controller.add(_isOnline);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
