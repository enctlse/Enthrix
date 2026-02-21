import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:tor_hidden_service/tor_hidden_service.dart';
import 'p2p_service.dart';

class TorService extends ChangeNotifier {
  static final TorService _instance = TorService._internal();
  factory TorService() => _instance;
  TorService._internal();

  late TorHiddenService _torService;
  final P2pService _p2pService = P2pService();
  
  int _socksPort = -1;
  int _httpTunnelPort = -1;
  
  bool _isEnabled = false;
  bool _isConnected = false;
  bool _isStarting = false;
  bool _isChecking = false;
  String _statusMessage = '';
  String? _errorMessage;
  String _logs = '';
  double _bootstrapProgress = 0.0;

  HttpClient? _httpClient;
  IOClient? _ioClient;

  P2pService get p2pService => _p2pService;

  bool get isEnabled => _isEnabled;
  bool get isConnected => _isConnected;
  bool get isStarting => _isStarting;
  bool get isChecking => _isChecking;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  String get logs => _logs;
  double get bootstrapProgress => _bootstrapProgress;
  int get socksPort => _socksPort;
  String? _onionAddress;
  
  String? get onionAddress => _onionAddress;
  bool get isAvailable => _isEnabled && _isConnected && _socksPort > 0;

  Future<void> initialize({bool enabled = false}) async {
    _isEnabled = enabled;
    
    if (_isEnabled) {
      await startTor();
    }
    
    notifyListeners();
  }

  Future<void> startTor() async {
    if (_isStarting || _isConnected) return;
    
    _isStarting = true;
    _statusMessage = 'Инициализация Tor...';
    _bootstrapProgress = 0.0;
    _logs = '';
    _errorMessage = null;
    notifyListeners();

    try {
      _torService = TorHiddenService();
      
      _torService.onLog.listen((log) {
        _logs += '$log\n';
        
        if (log.toLowerCase().contains('bootstrapped')) {
          _bootstrapProgress = 100.0;
        } else if (log.toLowerCase().contains('done')) {
          _bootstrapProgress = 100.0;
        }
        
        notifyListeners();
      });
      
      _logs += 'Запуск Tor прокси...\n';
      
      await _torService.start();
      
      _socksPort = 9050;
      _httpTunnelPort = 9080;
      
      _logs += 'Tor SOCKS порт: $_socksPort\n';
      _logs += 'Tor HTTP Tunnel порт: $_httpTunnelPort\n';
      
      _statusMessage = 'Подключение к сети Tor...';
      notifyListeners();

      await _waitForBootstrap();
      
    } on PlatformException catch (e) {
      _handleError('Ошибка запуска Tor (${e.code}): ${e.message}');
    } catch (e) {
      _handleError('Ошибка запуска Tor: $e');
    }
  }

  Future<void> _waitForBootstrap() async {
    const maxAttempts = 180; // 3 минуты максимум
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;
      
      _bootstrapProgress = (attempts / maxAttempts) * 100;
      _statusMessage = 'Подключение к сети Tor... ${attempts}s';
      notifyListeners();
      
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _socksPort,
          timeout: const Duration(seconds: 2),
        );
        await socket.close();
        
        _isConnected = true;
        _isStarting = false;
        _bootstrapProgress = 100.0;
        _statusMessage = 'Подключено к Tor';
        _errorMessage = null;
        _createHttpClient();
        _logs += 'Tor успешно подключен\n';
        
        _logs += 'Получение .onion адреса...\n';
        try {
          final hostname = await _torService.getOnionHostname();
          if (hostname != null) {
            _onionAddress = hostname;
            _logs += 'Ваш .onion адрес: $hostname\n';
            
            _logs += 'Запуск P2P сервиса...\n';
            await _p2pService.initialize(_onionAddress, socksPort: _socksPort);
            _logs += 'P2P сервис запущен на порту $_socksPort\n';
          }
        } catch (e) {
          _logs += 'Не удалось получить .onion адрес: $e\n';
        }
        
        notifyListeners();
        return;
      } catch (e) {
        // Tor still starting
      }
    }
    
    _handleError('Превышено время ожидания подключения к Tor');
  }

  void _createHttpClient() {
    try {
      _httpClient = HttpClient();
      
      // Use HTTP tunnel (9080) instead of SOCKS5 for HTTP requests
      _httpClient!.findProxy = (uri) {
        return 'PROXY 127.0.0.1:$_httpTunnelPort';
      };
      
      _ioClient = IOClient(_httpClient);
      _logs += 'HTTP клиент создан (HTTP tunnel: $_httpTunnelPort)\n';
    } catch (e) {
      _errorMessage = 'Ошибка создания HTTP клиента: $e';
    }
  }

  Future<void> stopTor() async {
    try {
      await _torService.stop();
    } catch (e) {
      print('Error stopping Tor: $e');
    }
    
    await _disposeHttpClient();
    
    _isConnected = false;
    _isStarting = false;
    _bootstrapProgress = 0.0;
    _socksPort = -1;
    _httpTunnelPort = -1;
    _onionAddress = null;
    _statusMessage = 'Tor остановлен';
    _logs += 'Tor остановлен\n';
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    
    _isEnabled = enabled;
    _errorMessage = null;
    
    if (_isEnabled) {
      await startTor();
    } else {
      await stopTor();
    }
    
    notifyListeners();
  }

  Future<bool> checkConnection() async {
    if (!_isEnabled) {
      _isConnected = false;
      _statusMessage = 'Tor отключен';
      notifyListeners();
      return false;
    }

    if (!isAvailable) {
      _statusMessage = 'Tor еще не готов';
      notifyListeners();
      return false;
    }

    _isChecking = true;
    _errorMessage = null;
    _statusMessage = 'Проверка подключения...';
    notifyListeners();

    try {
      final response = await _makeTorRequest(
        'https://check.torproject.org/api/ip',
        timeout: const Duration(seconds: 30),
      );

      if (response != null && response.statusCode == 200) {
        _isConnected = true;
        _statusMessage = 'Подключено к Tor';
        _errorMessage = null;
      } else {
        _isConnected = false;
        _statusMessage = 'Нет подключения к Tor';
        _errorMessage = 'Проверьте подключение';
      }
    } catch (e) {
      _isConnected = false;
      _statusMessage = 'Ошибка подключения';
      _errorMessage = _getErrorMessage(e);
    } finally {
      _isChecking = false;
      notifyListeners();
    }

    return _isConnected;
  }

  Future<http.Response?> _makeTorRequest(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_ioClient == null) {
      _createHttpClient();
    }

    try {
      final response = await _ioClient!
          .get(Uri.parse(url))
          .timeout(timeout);
      return response;
    } catch (e) {
      print('Tor request error: $e');
      rethrow;
    }
  }

  Future<http.Response?> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isAvailable) {
      throw Exception('Tor не доступен. Дождитесь подключения.');
    }

    try {
      return await _ioClient!
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
    } catch (e) {
      print('Tor GET error: $e');
      rethrow;
    }
  }

  Future<http.Response?> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isAvailable) {
      throw Exception('Tor не доступен. Дождитесь подключения.');
    }

    try {
      return await _ioClient!
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(timeout);
    } catch (e) {
      print('Tor POST error: $e');
      rethrow;
    }
  }

  Future<String?> getCurrentIp() async {
    if (!isAvailable) return null;

    try {
      final response = await get('https://api.ipify.org?format=json');
      if (response != null && response.statusCode == 200) {
        final body = response.body;
        final ipMatch = RegExp(r'"ip"\s*:\s*"([^"]+)"').firstMatch(body);
        return ipMatch?.group(1);
      }
    } catch (e) {
      print('Error getting IP: $e');
    }
    return null;
  }

  Future<String?> getOnionHostname() async {
    if (!isConnected) return null;
    try {
      return await _torService.getOnionHostname();
    } catch (e) {
      print('Error getting onion hostname: $e');
      return null;
    }
  }

  HttpClient? getTorHttpClient() {
    if (!isAvailable) return null;
    return _torService.getSecureTorClient();
  }

  void _handleError(String message) {
    _isStarting = false;
    _isConnected = false;
    _errorMessage = message;
    _statusMessage = 'Ошибка';
    _logs += 'ERROR: $message\n';
    print(message);
    notifyListeners();
  }

  String _getErrorMessage(dynamic error) {
    if (error is SocketException) {
      return 'Не удалось подключиться. Попробуйте перезапустить Tor.';
    } else if (error is TimeoutException) {
      return 'Превышено время ожидания. Tor работает медленно.';
    } else if (error is HandshakeException) {
      return 'Ошибка SSL-соединения.';
    } else {
      return 'Ошибка: $error';
    }
  }

  Future<void> _disposeHttpClient() async {
    _ioClient?.close();
    _httpClient?.close();
    _ioClient = null;
    _httpClient = null;
  }

  @override
  void dispose() {
    stopTor();
    super.dispose();
  }
}
