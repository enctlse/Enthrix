import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tor_hidden_service/tor_hidden_service.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum P2pConnectionStatus {
  offline,
  connecting,
  online,
  pending,
}

class P2pContact {
  final String onionAddress;
  P2pConnectionStatus status;
  String? displayName;
  DateTime addedAt;
  bool confirmed;

  P2pContact({
    required this.onionAddress,
    this.status = P2pConnectionStatus.pending,
    this.displayName,
    DateTime? addedAt,
    this.confirmed = false,
  }) : addedAt = addedAt ?? DateTime.now();
}

class P2pMessage {
  final String id;
  final String senderOnion;
  final String content;
  final DateTime timestamp;
  final bool isMine;

  P2pMessage({
    required this.id,
    required this.senderOnion,
    required this.content,
    required this.timestamp,
    required this.isMine,
  });
}

class P2pService extends ChangeNotifier {
  static final P2pService _instance = P2pService._internal();
  factory P2pService() => _instance;
  P2pService._internal();

  final AuthService _authService = AuthService();
  
  HttpServer? _server;
  List<P2pContact> _contacts = [];
  final Map<String, Socket> _connections = {};
  final Map<String, List<P2pMessage>> _messages = {};
  
  String? _myOnionAddress;
  bool _isRunning = false;
  int _serverPort = 8080;
  int _socksPort = 9050;
  
  final _messageController = StreamController<P2pMessage>.broadcast();
  Stream<P2pMessage> get messageStream => _messageController.stream;
  
  final _statusController = StreamController<Map<String, P2pConnectionStatus>>.broadcast();
  Stream<Map<String, P2pConnectionStatus>> get statusStream => _statusController.stream;

  final _logsController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get logsStream => _logsController.stream;

  String? get myOnionAddress => _myOnionAddress;
  List<P2pContact> get contacts => List.unmodifiable(_contacts);
  bool get isRunning => _isRunning;
  int get serverPort => _serverPort;

  Future<void> initialize(String? torOnionAddress, {int socksPort = 9050}) async {
    _myOnionAddress = torOnionAddress;
    _socksPort = socksPort;
    print('P2P initializing with SOCKS port: $_socksPort');
    if (_myOnionAddress != null) {
      await _saveOnionToProfile();
      await _startServer();
    }
  }

  Future<void> _saveOnionToProfile() async {
    final user = _authService.currentUser;
    if (user != null && _myOnionAddress != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'onionAddress': _myOnionAddress,
        });
      } catch (e) {
        print('Error saving onion address: $e');
      }
    }
  }

  Future<void> _startServer() async {
    if (_isRunning) return;
    
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      _isRunning = true;
      print('P2P Server started on port $_serverPort');
      notifyListeners();
      
      _server!.listen(_handleIncomingConnection, onError: (e) {
        print('Server error: $e');
      });
    } catch (e) {
      print('Error starting P2P server: $e');
    }
  }

  void _handleIncomingConnection(HttpRequest request) async {
    print('Incoming connection from: ${request.connectionInfo?.remoteAddress}');
    try {
      final content = await utf8.decodeStream(request);
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      print('Received data: $data');
      
      final type = data['type'] as String?;
      
      if (type == 'handshake') {
        final onion = data['onion'] as String?;
        final name = data['name'] as String?;
        
        if (onion != null) {
          _handleNewContact(onion, name, confirmed: true);
          
          request.response.write(jsonEncode({
            'type': 'handshake_ack',
            'onion': _myOnionAddress,
            'name': _authService.currentUser?.displayName ?? 'Unknown',
          }));
        }
      } else if (type == 'message') {
        final senderOnion = data['from'] as String?;
        final content = data['content'] as String?;
        
        if (senderOnion != null && content != null) {
          try {
            final decoded = utf8.decode(base64Decode(content));
            
            final message = P2pMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              senderOnion: senderOnion,
              content: decoded,
              timestamp: DateTime.now(),
              isMine: false,
            );
            
            _addMessage(senderOnion, message);
            _messageController.add(message);
            
            request.response.write(jsonEncode({'type': 'ack'}));
          } catch (e) {
            print('Error processing message: $e');
          }
        }
      }
      
      await request.response.close();
    } catch (e) {
      print('Error handling incoming connection: $e');
    }
  }

  void _handleNewContact(String onion, String? name, {required bool confirmed}) {
    final existingIndex = _contacts.indexWhere((c) => c.onionAddress == onion);
    
    if (existingIndex >= 0) {
      final wasOnline = _contacts[existingIndex].status == P2pConnectionStatus.online;
      _contacts[existingIndex].status = confirmed 
          ? P2pConnectionStatus.online 
          : P2pConnectionStatus.pending;
      _contacts[existingIndex].confirmed = confirmed;
      _contacts[existingIndex].displayName = name;
      
      if (!wasOnline && confirmed) {
        _notifyStatusChange();
      }
    } else {
      _contacts.add(P2pContact(
        onionAddress: onion,
        status: confirmed ? P2pConnectionStatus.online : P2pConnectionStatus.pending,
        displayName: name,
        confirmed: confirmed,
      ));
      
      _notifyStatusChange();
    }
    
    notifyListeners();
  }

  void _addMessage(String onion, P2pMessage message) {
    if (!_messages.containsKey(onion)) {
      _messages[onion] = [];
    }
    _messages[onion]!.add(message);
  }

  List<P2pMessage> getMessages(String onionAddress) {
    return _messages[onionAddress] ?? [];
  }

  final List<String> _connectionLogs = [];
  List<String> get connectionLogs => _connectionLogs;

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final log = '[$timestamp] $message';
    print(log);
    _connectionLogs.add(log);
    // Keep only last 50 logs
    if (_connectionLogs.length > 50) {
      _connectionLogs.removeAt(0);
    }
    _logsController.add(List.unmodifiable(_connectionLogs));
  }

  Future<void> addContact(String onionAddress) async {
    _addLog('Adding contact: $onionAddress');
    
    if (onionAddress == _myOnionAddress) {
      _addLog('ERROR: Cannot add yourself');
      throw Exception('Нельзя добавить самого себя');
    }
    
    final existing = _contacts.where((c) => c.onionAddress == onionAddress);
    if (existing.isNotEmpty) {
      _addLog('Contact already exists, status: ${existing.first.status}');
      if (existing.first.status == P2pConnectionStatus.offline) {
        _addLog('Retrying connection...');
        _startPeriodicCheck(onionAddress);
      }
      return;
    }
    
    _addLog('Creating new contact with status: connecting');
    _contacts.add(P2pContact(
      onionAddress: onionAddress,
      status: P2pConnectionStatus.connecting,
    ));
    notifyListeners();
    
    _addLog('Sending handshake...');
    await _sendHandshake(onionAddress);
    
    _addLog('Starting periodic check');
    _startPeriodicCheck(onionAddress);
  }

  void _startPeriodicCheck(String onionAddress) {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      
      if (!_contacts.any((c) => c.onionAddress == onionAddress)) {
        return false;
      }
      
      final contact = _contacts.firstWhere((c) => c.onionAddress == onionAddress);
      if (contact.status == P2pConnectionStatus.offline) {
        await _retryConnection(onionAddress);
      }
      
      return true;
    });
  }

  Future<void> _retryConnection(String onionAddress) async {
    try {
      final socket = await _connectViaSocks(onionAddress, _serverPort);
      
      _connections[onionAddress] = socket;
      
      socket.write(jsonEncode({
        'type': 'handshake',
        'onion': _myOnionAddress,
        'name': _authService.currentUser?.displayName ?? 'Unknown',
      }));
      
      _updateContactStatus(onionAddress, P2pConnectionStatus.pending);
    } catch (e) {
      print('Retry connection failed: $e');
      _updateContactStatus(onionAddress, P2pConnectionStatus.offline);
    }
  }

  Future<Socket> _connectViaSocks(String onionHost, int port) async {
    _addLog('SOCKS5: Connecting to proxy 127.0.0.1:$_socksPort for $onionHost:$port');
    
    // Use RawSocket for low-level control
    _addLog('SOCKS5: Step 1 - Creating RawSocket...');
    final rawSocket = await RawSocket.connect('127.0.0.1', _socksPort, timeout: const Duration(seconds: 30));
    _addLog('SOCKS5: RawSocket connected');
    
    // SOCKS5 handshake - request authentication
    _addLog('SOCKS5: Step 2 - Sending auth request...');
    rawSocket.write(Uint8List.fromList([0x05, 0x01, 0x00]));
    
    // Read auth response
    _addLog('SOCKS5: Step 3 - Reading auth response...');
    final authResponse = await _readFromRawSocket(rawSocket, 2);
    _addLog('SOCKS5: Auth response: ${authResponse.toList()}');
    if (authResponse[0] != 0x05) {
      throw Exception('Invalid SOCKS version: ${authResponse[0]}');
    }
    if (authResponse[1] != 0x00) {
      throw Exception('Authentication failed: ${authResponse[1]}');
    }
    
    // Send CONNECT request
    _addLog('SOCKS5: Step 4 - Sending CONNECT request...');
    final domainBytes = utf8.encode(onionHost);
    final request = BytesBuilder();
    request.add([0x05, 0x01, 0x00, 0x03]);
    request.add([domainBytes.length]);
    request.add(domainBytes);
    request.add([(port >> 8) & 0xFF, port & 0xFF]);
    rawSocket.write(request.toBytes());
    
    // Read response
    _addLog('SOCKS5: Step 5 - Reading CONNECT response...');
    final response = await _readFromRawSocket(rawSocket, 4);
    _addLog('SOCKS5: CONNECT response: ${response.toList()}');
    if (response[0] != 0x05) {
      throw Exception('Invalid SOCKS response version: ${response[0]}');
    }
    if (response[1] != 0x00) {
      throw Exception('SOCKS connection failed: ${response[1]}');
    }
    
    // Read rest of response
    _addLog('SOCKS5: Step 6 - Reading address/port...');
    final atyp = response[3];
    if (atyp == 0x01) {
      await _readFromRawSocket(rawSocket, 4 + 2);
    } else if (atyp == 0x03) {
      final domainLen = (await _readFromRawSocket(rawSocket, 1))[0];
      await _readFromRawSocket(rawSocket, domainLen + 2);
    } else if (atyp == 0x04) {
      await _readFromRawSocket(rawSocket, 16 + 2);
    }
    
    _addLog('SOCKS5: Connected! Converting to Socket...');
    
    // Convert RawSocket to regular Socket
    final socket = await Socket.connect('127.0.0.1', _socksPort);
    rawSocket.close();
    
    return socket;
  }

  Future<Uint8List> _readFromRawSocket(RawSocket socket, int count) async {
    final buffer = BytesBuilder();
    final completer = Completer<Uint8List>();
    StreamSubscription? subscription;
    
    subscription = socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          final data = socket.read();
          if (data != null && data.isNotEmpty) {
            buffer.add(data);
            if (buffer.length >= count && !completer.isCompleted) {
              subscription?.cancel();
              completer.complete(Uint8List.fromList(buffer.toBytes().sublist(0, count)));
            }
          }
        } else if (event == RawSocketEvent.closed) {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(Exception('Socket closed unexpectedly'));
          }
        }
      },
      onError: (e) {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
    );
    
    // Timeout after 30 seconds
    return completer.future.timeout(Duration(seconds: 30), onTimeout: () {
      subscription?.cancel();
      throw Exception('Timeout reading from socket');
    });
  }

  Future<void> _sendHandshake(String onionAddress) async {
    _addLog('Handshake started for $onionAddress');
    try {
      _updateContactStatus(onionAddress, P2pConnectionStatus.connecting);
      _addLog('Status updated to CONNECTING');
      _addLog('Connecting to $onionAddress:$_serverPort via SOCKS5 ($_socksPort)...');
      
      final socket = await _connectViaSocks(onionAddress, _serverPort);
      
      print('P2P: Connected to $onionAddress!');
      _connections[onionAddress] = socket;
      
      socket.write(jsonEncode({
        'type': 'handshake',
        'onion': _myOnionAddress,
        'name': _authService.currentUser?.displayName ?? 'Unknown',
      }));
      
      socket.listen((data) async {
        try {
          final response = utf8.decode(data);
          final data_ = jsonDecode(response) as Map<String, dynamic>;
          
          print('Received: $data_');
          
          if (data_['type'] == 'handshake_ack') {
            final name = data_['name'] as String?;
            _handleNewContact(onionAddress, name, confirmed: true);
          } else if (data_['type'] == 'handshake') {
            final name = data_['name'] as String?;
            _handleNewContact(onionAddress, name, confirmed: true);
            
            socket.write(jsonEncode({
              'type': 'handshake_ack',
              'onion': _myOnionAddress,
              'name': _authService.currentUser?.displayName ?? 'Unknown',
            }));
          }
        } catch (e) {
          print('Error parsing response: $e');
        }
      }, onError: (e) {
        print('Socket error: $e');
        _updateContactStatus(onionAddress, P2pConnectionStatus.offline);
      });
      
      _updateContactStatus(onionAddress, P2pConnectionStatus.pending);
    } catch (e, stackTrace) {
      _addLog('ERROR connecting to $onionAddress: $e');
      _addLog('Stack trace: $stackTrace');
      _updateContactStatus(onionAddress, P2pConnectionStatus.offline);
    }
  }

  void _updateContactStatus(String onionAddress, P2pConnectionStatus status) {
    final index = _contacts.indexWhere((c) => c.onionAddress == onionAddress);
    if (index >= 0) {
      _contacts[index].status = status;
      _notifyStatusChange();
      notifyListeners();
    }
  }

  void _notifyStatusChange() {
    final statusMap = <String, P2pConnectionStatus>{};
    for (final contact in _contacts) {
      statusMap[contact.onionAddress] = contact.status;
    }
    _statusController.add(statusMap);
  }

  Future<void> sendMessage(String onionAddress, String content) async {
    final contact = _contacts.firstWhere(
      (c) => c.onionAddress == onionAddress,
      orElse: () => throw Exception('Контакт не найден'),
    );
    
    if (contact.status != P2pConnectionStatus.online) {
      throw Exception('Контакт не в сети');
    }
    
    try {
      final encoded = base64Encode(utf8.encode(content));
      final socket = _connections[onionAddress];
      
      if (socket != null) {
        socket.write(jsonEncode({
          'type': 'message',
          'from': _myOnionAddress,
          'content': encoded,
        }));
        
        final message = P2pMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderOnion: _myOnionAddress!,
          content: content,
          timestamp: DateTime.now(),
          isMine: true,
        );
        
        _addMessage(onionAddress, message);
        _messageController.add(message);
      }
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  Future<void> removeContact(String onionAddress) async {
    _contacts.removeWhere((c) => c.onionAddress == onionAddress);
    _messages.remove(onionAddress);
    _connections[onionAddress]?.destroy();
    _connections.remove(onionAddress);
    _notifyStatusChange();
    notifyListeners();
  }

  Future<void> stop() async {
    await _server?.close();
    for (final socket in _connections.values) {
      socket.destroy();
    }
    _connections.clear();
    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _messageController.close();
    _statusController.close();
    _logsController.close();
    super.dispose();
  }
}
