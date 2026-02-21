import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async' show Timer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message_model.dart';
import 'auth_service.dart';
import 'encryption_service.dart';


class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final EncryptionService _encryptionService = EncryptionService();


  final Map<String, List<MessageModel>> _localMessages = {};
  final _messageController =
      StreamController<Map<String, List<MessageModel>>>.broadcast();
  StreamSubscription? _incomingMessagesSubscription;
  StreamSubscription? _typingStatusSubscription;


  final Set<String> _activeChats = {};
  final Map<String, Timer> _selfDestructTimers = {};


  bool _isInitialized = false;
  String? _initializedUserId;
  Timer? _pollingTimer;
  SharedPreferences? _prefs;

  Stream<Map<String, List<MessageModel>>> get messageStream =>
      _messageController.stream;

  final _typingStatusController = StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get typingStatusStream => _typingStatusController.stream;

  Future<void> _saveChatsToStorage() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        print('MSG: Cannot save chats - no current user');
        return;
      }

      final storageKey = 'chats_${currentUser.uid}';
      final chatsData = <String, dynamic>{};

      for (final entry in _localMessages.entries) {
        chatsData[entry.key] = entry.value.map((m) => m.toLocalStorageMap()).toList();
      }

      final jsonString = jsonEncode(chatsData);
      await _prefs!.setString(storageKey, jsonString);
      print('MSG: Saved ${_localMessages.length} chats to storage (key: $storageKey, size: ${jsonString.length} bytes)');
    } catch (e) {
      print('MSG: Error saving chats to storage: $e');
    }
  }

  Future<void> _loadChatsFromStorage() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        print('MSG: Cannot load chats - no current user');
        return;
      }

      final storageKey = 'chats_${currentUser.uid}';
      final jsonString = _prefs!.getString(storageKey);

      print('MSG: Loading chats from storage (key: $storageKey)');
      print('MSG: Raw data from storage: ${jsonString != null ? "found (${jsonString.length} bytes)" : "null"}');

      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final chatsData = jsonDecode(jsonString) as Map<String, dynamic>;
          print('MSG: Decoded ${chatsData.length} chat entries');
          
          _localMessages.clear();
          int totalMessages = 0;
          for (final entry in chatsData.entries) {
            try {
              final messagesList = entry.value as List;
              print('MSG: Processing chat ${entry.key} with ${messagesList.length} messages');
              final messages = messagesList
                  .map((m) => MessageModel.fromLocalStorageMap(m as Map<String, dynamic>))
                  .toList();
              _localMessages[entry.key] = messages;
              _activeChats.add(entry.key);
              totalMessages += messages.length;
            } catch (e, stackTrace) {
              print('MSG: Error parsing chat ${entry.key}: $e');
              print('MSG: Stack trace: $stackTrace');
            }
          }

          print('MSG: Successfully loaded ${_localMessages.length} chats with $totalMessages total messages');
          _messageController.add(Map.from(_localMessages));
        } catch (e, stackTrace) {
          print('MSG: Error decoding JSON: $e');
          print('MSG: Stack trace: $stackTrace');
        }
      } else {
        print('MSG: No chats found in storage for key: $storageKey');
      }
    } catch (e, stackTrace) {
      print('MSG: Error loading chats from storage: $e');
      print('MSG: Stack trace: $stackTrace');
    }
  }

  Future<void> initialize() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      print('MessageService: No current user, skipping initialization');
      return;
    }


    if (_isInitialized && _initializedUserId == currentUser.uid) {
      print('MessageService: Already initialized for user ${currentUser.uid}');
      return;
    }

    print('MessageService: Initializing for user ${currentUser.uid}');


    await _loadChatsFromStorage();


    await _encryptionService.initialize(currentUser.uid);


    _startListeningForMessages(currentUser.uid);


    _startListeningForReadReceipts(currentUser.uid);

    _isInitialized = true;
    _initializedUserId = currentUser.uid;
    print(
      'MessageService: Initialization complete for UID: ${currentUser.uid}',
    );


    await _fetchPendingMessages(currentUser.uid);


    _startPolling(currentUser.uid);
  }

  void _startPolling(String userId) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isInitialized || _initializedUserId != userId) {
        timer.cancel();
        return;
      }
      await _fetchPendingMessages(userId);
    });
    print('MSG: Started polling every 5 seconds');
  }

  Future<void> _fetchPendingMessages(String userId) async {
    print('MSG: Fetching pending messages for user: $userId');
    print('MSG: Path: messages/$userId/incoming');
    try {
      final snapshot = await _firestore
          .collection('messages')
          .doc(userId)
          .collection('incoming')
          .get();

      print('MSG: Found ${snapshot.docs.length} pending messages');
      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          print(
            'MSG: Message ID: ${doc.id}, sender: ${doc['senderId']}, delivered: ${doc['delivered']}',
          );
        }
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['delivered'] == true) continue;

        try {
          final encryptedText = data['encryptedText'] as String?;
          if (encryptedText == null) continue;

          final plainText = _encryptionService.decryptMessage(encryptedText);

          final message = MessageModel(
            id: data['id'] ?? doc.id,
            chatId: data['chatId'] ?? data['senderId'] ?? 'unknown',
            senderId: data['senderId'] ?? '',
            receiverId: userId,
            text: plainText,
            encryptedText: encryptedText,
            timestamp:
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            type: data['type'] ?? 'text',
            status: MessageStatus.delivered,
          );

          final chatId = message.chatId;
          if (!_localMessages.containsKey(chatId)) {
            _localMessages[chatId] = [];
          }


          final existingIndex = _localMessages[chatId]!.indexWhere(
            (m) => m.id == message.id,
          );
          if (existingIndex == -1) {
            _localMessages[chatId]!.add(message);
            _activeChats.add(chatId);
          }


          await _markDelivered(userId, doc.id);
        } catch (e) {
          print('MSG: Error processing pending message: $e');
        }
      }


      if (snapshot.docs.isNotEmpty) {
        _messageController.add(Map.from(_localMessages));
        await _saveChatsToStorage();
        print(
          'MSG: Pending messages processed, total chats: ${_localMessages.length}',
        );
      }
    } catch (e) {
      print('MSG: Error fetching pending messages: $e');
    }
  }

  void ensureListening() {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    if (_incomingMessagesSubscription == null) {
      print('MessageService: Re-starting listener');
      _startListeningForMessages(currentUser.uid);
    }
  }

  Future<bool> sendMessage({
    required String receiverId,
    required String plainText,
    String? existingChatId,
    int? selfDestructSeconds,
    String? replyToMessageId,
    String? replyToText,
    String type = 'text',
  }) async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    final chatId =
        existingChatId ?? _generateChatId(currentUser.uid, receiverId);
    final isNewChat = !_activeChats.contains(chatId);


    String encryptedText;
    try {
      encryptedText = _encryptionService.encryptMessage(receiverId, plainText);
    } catch (e) {
      print('Encryption failed: $e');
      throw Exception('Failed to encrypt message. Public key not available.');
    }


    print('SEND: Creating message with replyToMessageId=$replyToMessageId, replyToText=$replyToText');
    
    final message = MessageModel(
      id: '${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: currentUser.uid,
      receiverId: receiverId,
      text: plainText,
      encryptedText: encryptedText,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      selfDestructSeconds: selfDestructSeconds,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      type: type,
    );


    if (!_localMessages.containsKey(chatId)) {
      _localMessages[chatId] = [];
    }
    _localMessages[chatId]!.add(message);
    _activeChats.add(chatId);
    _messageController.add(Map.from(_localMessages));
    

    await _saveChatsToStorage();

    try {
      print('=== SENDING MESSAGE ===');
      print('Sender UID: ${currentUser.uid}');
      print('Receiver UID: $receiverId');
      print('Message ID: ${message.id}');
      print('Chat ID: $chatId');
      print('Encrypted length: ${encryptedText.length}');
      print('Firestore path: messages/$receiverId/incoming/${message.id}');


      await _firestore
          .collection('messages')
          .doc(receiverId)
          .collection('incoming')
          .doc(message.id)
          .set(message.toServerMap());

      print('Message sent successfully!');


      await _updateMessageStatus(chatId, message.id, MessageStatus.sent);



      return isNewChat;
    } catch (e, stackTrace) {
      print('ERROR sending message: $e');
      print('Stack trace: $stackTrace');
      await _updateMessageStatus(chatId, message.id, MessageStatus.failed);
      throw Exception('Failed to send message: $e');
    }
  }

  void _startListeningForMessages(String userId) {
    print('=== STARTING LISTENER ===');
    print('For user: $userId');
    print('Path: messages/$userId/incoming');
    _incomingMessagesSubscription?.cancel();

    try {
      _incomingMessagesSubscription = _firestore
          .collection('messages')
          .doc(userId)
          .collection('incoming')
          .snapshots()
          .listen(
            (snapshot) async {
              print('=== SNAPSHOT RECEIVED ===');
              print('Changes: ${snapshot.docChanges.length}');
              print('Total docs: ${snapshot.docs.length}');
              print('From cache: ${snapshot.metadata.isFromCache}');

              for (var change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  final data = change.doc.data();
                  if (data == null) continue;


                  if (data['delivered'] == true) continue;

                  print('MSG: Processing ${change.doc.id}');

                  try {

                    final encryptedText = data['encryptedText'] as String?;
                    if (encryptedText == null) continue;

                    final plainText = _encryptionService.decryptMessage(
                      encryptedText,
                    );
                    print('MSG: Decrypted ok');


                    print('MSG: Reply data from server: replyToMessageId=${data['replyToMessageId']}, replyToText=${data['replyToText']}');
                    
                    final message = MessageModel(
                      id: data['id'] ?? change.doc.id,
                      chatId: data['chatId'] ?? data['senderId'] ?? 'unknown',
                      senderId: data['senderId'] ?? '',
                      receiverId: userId,
                      text: plainText,
                      encryptedText: encryptedText,
                      timestamp:
                          (data['timestamp'] as Timestamp?)?.toDate() ??
                          DateTime.now(),
                      type: data['type'] ?? 'text',
                      status: MessageStatus.delivered,
                      replyToMessageId: data['replyToMessageId'],
                      replyToText: data['replyToText'],
                    );
                    
                    print('MSG: Created message with replyToMessageId=${message.replyToMessageId}, replyToText=${message.replyToText}');


                    final chatId = message.chatId;
                    if (!_localMessages.containsKey(chatId)) {
                      _localMessages[chatId] = [];
                    }


                    final existingIndex = _localMessages[chatId]!.indexWhere(
                      (m) => m.id == message.id,
                    );
                    if (existingIndex == -1) {
                      _localMessages[chatId]!.add(message);
                      _activeChats.add(chatId);
                      print('MSG: Added to local storage');
                    }


                    await _markDelivered(userId, change.doc.id);


                    _messageController.add(Map.from(_localMessages));
                    await _saveChatsToStorage();
                    print('MSG: Listeners notified and chats saved');
                  } catch (e) {
                    print('MSG ERROR: $e');
                  }
                }
              }
            },
            onError: (error) {
              print('MSG Listener ERROR: $error');
            },
          );
      print('Listener started successfully');
    } catch (e) {
      print('Failed to start listener: $e');
    }
  }

  Future<void> _markDelivered(String userId, String messageId) async {
    try {

      await _firestore
          .collection('messages')
          .doc(userId)
          .collection('incoming')
          .doc(messageId)
          .update({'delivered': true});


      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await _firestore
              .collection('messages')
              .doc(userId)
              .collection('incoming')
              .doc(messageId)
              .delete();
          print('Message $messageId deleted from server');
        } catch (e) {
          print('Error deleting message: $e');
        }
      });
    } catch (e) {
      print('Error marking message as delivered: $e');
    }
  }

  String _generateChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_${userId2}'
        : '${userId2}_${userId1}';
  }

  Future<void> _updateMessageStatus(
    String chatId,
    String messageId,
    MessageStatus status,
  ) async {
    if (_localMessages.containsKey(chatId)) {
      final index = _localMessages[chatId]!.indexWhere(
        (m) => m.id == messageId,
      );
      if (index != -1) {
        _localMessages[chatId]![index] = _localMessages[chatId]![index]
            .copyWith(status: status);
        _messageController.add(Map.from(_localMessages));
        await _saveChatsToStorage();
      }
    }
  }

  Future<void> markMessagesAsRead(String chatId) async {
    if (_localMessages.containsKey(chatId)) {
      final updatedMessages = _localMessages[chatId]!.map((msg) {
        if (msg.status == MessageStatus.delivered) {
          return msg.copyWith(
            status: MessageStatus.read,
            readAt: DateTime.now(),
          );
        }
        return msg;
      }).toList();

      _localMessages[chatId] = updatedMessages;
      _messageController.add(Map.from(_localMessages));
      await _saveChatsToStorage();


      final readMessages = updatedMessages.where((msg) => 
        msg.status == MessageStatus.read && 
        msg.readAt != null &&
        msg.senderId != _authService.currentUser?.uid
      ).toList();

      for (final msg in readMessages) {
        await _sendReadReceipt(msg.senderId, msg.id);
      }
    }
  }

  Future<void> _sendReadReceipt(String senderId, String messageId) async {
    try {
      await _firestore
          .collection('readReceipts')
          .doc(senderId)
          .collection('receipts')
          .doc(messageId)
          .set({
        'messageId': messageId,
        'readAt': Timestamp.fromDate(DateTime.now()),
        'timestamp': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      print('MSG: Error sending read receipt: $e');
    }
  }

  void _startListeningForReadReceipts(String userId) {
    _firestore
        .collection('readReceipts')
        .doc(userId)
        .collection('receipts')
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final messageId = data['messageId'] as String?;
            final readAt = (data['readAt'] as Timestamp?)?.toDate();
            
            if (messageId != null && readAt != null) {

              for (final entry in _localMessages.entries) {
                final index = entry.value.indexWhere((m) => m.id == messageId);
                if (index != -1) {
                  final msg = entry.value[index];
                  if (msg.status != MessageStatus.read) {
                    entry.value[index] = msg.copyWith(
                      status: MessageStatus.read,
                      readAt: readAt,
                    );
                    _messageController.add(Map.from(_localMessages));
                    await _saveChatsToStorage();
                    

                    await change.doc.reference.delete();
                  }
                  break;
                }
              }
            }
          }
        }
      }
    });
  }

  List<MessageModel> getMessages(String chatId) {
    return _localMessages[chatId] ?? [];
  }

  List<Map<String, dynamic>> getUserChats(String userId) {
    final chats = <Map<String, dynamic>>[];

    print('MSG: getUserChats called, _localMessages has ${_localMessages.length} entries');

    for (final entry in _localMessages.entries) {
      final chatId = entry.key;
      final messages = entry.value;

      if (messages.isEmpty) continue;


      final lastMessage = messages.last;


      String otherUserId = lastMessage.senderId == userId
          ? lastMessage.receiverId
          : lastMessage.senderId;

      chats.add({
        'chatId': chatId,
        'otherUserId': otherUserId,
        'lastMessage': lastMessage.text,
        'lastMessageTime': Timestamp.fromDate(lastMessage.timestamp),
      });
    }

    print('MSG: Returning ${chats.length} chats');


    chats.sort(
      (a, b) => (b['lastMessageTime'] as Timestamp).compareTo(
        a['lastMessageTime'] as Timestamp,
      ),
    );

    return chats;
  }

  Future<Map<String, dynamic>?> getChatInfo(
    String chatId,
    String currentUserId,
  ) async {
    final messages = _localMessages[chatId];
    if (messages == null || messages.isEmpty) return null;


    final message = messages.first;
    final otherUserId = message.senderId == currentUserId
        ? message.receiverId
        : message.senderId;

    return {'chatId': chatId, 'otherUserId': otherUserId};
  }

  Future<void> retrySendMessage(String chatId, String messageId) async {
    if (!_localMessages.containsKey(chatId)) return;

    final message = _localMessages[chatId]!.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw Exception('Message not found'),
    );

    await _updateMessageStatus(chatId, messageId, MessageStatus.sending);

    try {
      await _firestore
          .collection('messages')
          .doc(message.receiverId)
          .collection('incoming')
          .doc(message.id)
          .set(message.toServerMap());

      await _updateMessageStatus(chatId, messageId, MessageStatus.sent);
    } catch (e) {
      await _updateMessageStatus(chatId, messageId, MessageStatus.failed);
      throw Exception('Retry failed: $e');
    }
  }

  void stopListening() {
    print('MessageService: Stopping listener');
    _incomingMessagesSubscription?.cancel();
    _incomingMessagesSubscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void clear() {
    print('MessageService: Clearing all data');
    stopListening();
    _localMessages.clear();
    _activeChats.clear();
    _encryptionService.clearMemoryKeys();
    _isInitialized = false;
    _initializedUserId = null;
  }

  Future<void> clearWithKeys() async {
    print('MessageService: Clearing all data and keys');
    stopListening();
    _localMessages.clear();
    _activeChats.clear();
    await _encryptionService.clearKeys(deleteFromStorage: true);
    _isInitialized = false;
    _initializedUserId = null;
  }

  void dispose() {
    print('MessageService: Disposing');
    clear();
    _messageController.close();
    _typingStatusController.close();
  }

  // ========== TYPING STATUS ==========
  void startListeningForTypingStatus(String chatId, String currentUserId) {
    _typingStatusSubscription?.cancel();
    
    final otherUserId = chatId.replaceFirst(currentUserId, '').replaceFirst('_', '');
    
    _typingStatusSubscription = _firestore
        .collection('typingStatus')
        .doc(chatId)
        .collection('users')
        .doc(otherUserId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        final isTyping = data?['isTyping'] ?? false;
        _typingStatusController.add({chatId: isTyping});
      }
    });
  }

  Future<void> setTypingStatus(String chatId, bool isTyping) async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('typingStatus')
          .doc(chatId)
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'isTyping': isTyping,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      });

      // Auto-clear typing status after 5 seconds
      if (isTyping) {
        Future.delayed(const Duration(seconds: 5), () async {
          await _firestore
              .collection('typingStatus')
              .doc(chatId)
              .collection('users')
              .doc(currentUser.uid)
              .update({'isTyping': false});
        });
      }
    } catch (e) {
      print('Error setting typing status: $e');
    }
  }

  void stopListeningForTypingStatus() {
    _typingStatusSubscription?.cancel();
    _typingStatusSubscription = null;
  }

  // ========== SELF-DESTRUCT ==========
  void startSelfDestructTimer(String chatId, MessageModel message) {
    if (message.selfDestructSeconds == null || message.selfDestructSeconds! <= 0) return;

    final timerKey = '${chatId}_${message.id}';
    _selfDestructTimers[timerKey]?.cancel();

    _selfDestructTimers[timerKey] = Timer(
      Duration(seconds: message.selfDestructSeconds!),
      () async {
        await _deleteMessage(chatId, message.id);
      },
    );
  }

  Future<void> _deleteMessage(String chatId, String messageId) async {
    if (_localMessages.containsKey(chatId)) {
      final index = _localMessages[chatId]!.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _localMessages[chatId]![index] = _localMessages[chatId]![index].copyWith(
          isDeleted: true,
          text: '🕐 Сообщение удалено',
        );
        _messageController.add(Map.from(_localMessages));
        await _saveChatsToStorage();
      }
    }
    _selfDestructTimers.remove('${chatId}_${messageId}');
  }

  Future<void> deleteMessageForEveryone(String chatId, String messageId) async {
    if (_localMessages.containsKey(chatId)) {
      final index = _localMessages[chatId]!.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _localMessages[chatId]![index];
        _localMessages[chatId]![index] = message.copyWith(
          isDeleted: true,
          text: '🕐 Сообщение удалено',
        );
        _messageController.add(Map.from(_localMessages));
        await _saveChatsToStorage();

        // Send delete signal to other user
        await _firestore
            .collection('deleteSignals')
            .doc(message.receiverId == _authService.currentUser?.uid 
                ? message.senderId 
                : message.receiverId)
            .collection('signals')
            .doc(messageId)
            .set({
          'messageId': messageId,
          'chatId': chatId,
          'timestamp': Timestamp.fromDate(DateTime.now()),
        });
      }
    }
  }

  void startListeningForDeleteSignals(String userId) {
    _firestore
        .collection('deleteSignals')
        .doc(userId)
        .collection('signals')
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final messageId = data['messageId'] as String?;
            final chatId = data['chatId'] as String?;
            
            if (messageId != null && chatId != null) {
              if (_localMessages.containsKey(chatId)) {
                final index = _localMessages[chatId]!.indexWhere((m) => m.id == messageId);
                if (index != -1) {
                  _localMessages[chatId]![index] = _localMessages[chatId]![index].copyWith(
                    isDeleted: true,
                    text: '🕐 Сообщение удалено',
                  );
                  _messageController.add(Map.from(_localMessages));
                  await _saveChatsToStorage();
                }
              }
              // Delete the signal after processing
              await change.doc.reference.delete();
            }
          }
        }
      }
    });
  }

  // ========== SEARCH ==========
  List<MessageModel> searchMessages(String chatId, String query) {
    if (!_localMessages.containsKey(chatId)) return [];
    
    final lowerQuery = query.toLowerCase();
    return _localMessages[chatId]!
        .where((msg) => 
            !msg.isDeleted && 
            msg.text.toLowerCase().contains(lowerQuery))
        .toList();
  }

  List<Map<String, dynamic>> searchAllChats(String query) {
    final results = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase();
    
    for (final entry in _localMessages.entries) {
      final matchingMessages = entry.value
          .where((msg) => 
              !msg.isDeleted && 
              msg.text.toLowerCase().contains(lowerQuery))
          .toList();
      
      if (matchingMessages.isNotEmpty) {
        results.add({
          'chatId': entry.key,
          'messages': matchingMessages,
        });
      }
    }
    
    return results;
  }
}


final messageService = MessageService();
