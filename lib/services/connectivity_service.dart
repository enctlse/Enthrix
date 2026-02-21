import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOnline = true;
  bool _isChecking = false;
  String _statusMessage = '';
  Timer? _checkTimer;

  bool get isOnline => _isOnline;
  bool get isChecking => _isChecking;
  String get statusMessage => _statusMessage;

  void startMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(Duration(seconds: 5), (_) => checkConnection());
    checkConnection();
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> checkConnection() async {
    if (_isChecking) return;
    
    _isChecking = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(Duration(seconds: 5));
      
      final newStatus = response.statusCode == 204;
      if (_isOnline != newStatus) {
        _isOnline = newStatus;
        _statusMessage = _isOnline ? 'Онлайн' : 'Ожидание сети...';
        notifyListeners();
      }
    } catch (e) {
      if (_isOnline) {
        _isOnline = false;
        _statusMessage = 'Ожидание сети...';
        notifyListeners();
      }
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
}
