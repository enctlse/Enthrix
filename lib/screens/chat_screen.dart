import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/encryption_service.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final String userName;
  final String? chatId;
  final String? otherUserId;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const ChatScreen({
    super.key,
    required this.userName,
    this.chatId,
    this.otherUserId,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _authService = AuthService();
  final _messageService = messageService;
  final _encryptionService = EncryptionService();
  final _firestore = FirebaseFirestore.instance;

  String? _currentChatId;
  String? _otherUserId;
  bool _isLoading = true;
  List<MessageModel> _messages = [];
  StreamSubscription? _messageSubscription;
  Stream<DocumentSnapshot>? _userStatusStream;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    if (widget.chatId != null) {
      _currentChatId = widget.chatId;
      final chatInfo = await _messageService.getChatInfo(
        widget.chatId!,
        _authService.currentUser!.uid,
      );
      if (chatInfo != null) {
        _otherUserId = chatInfo['otherUserId'] as String;
        _importPublicKeyIfNeeded(_otherUserId!);
      }
      _loadMessages();
    } else if (widget.otherUserId != null) {
      _otherUserId = widget.otherUserId;
      _currentChatId = _generateChatId(
        _authService.currentUser!.uid,
        widget.otherUserId!,
      );
      _importPublicKeyIfNeeded(_otherUserId!);
    }

    if (_otherUserId != null) {
      _userStatusStream = _firestore
          .collection('users')
          .doc(_otherUserId)
          .snapshots();
    }

    _messageSubscription = _messageService.messageStream.listen((allMessages) {
      if (mounted && _currentChatId != null) {
        setState(() {
          _messages = allMessages[_currentChatId] ?? [];
        });
        _scrollToBottom();
        
        if (_messages.isNotEmpty) {
          final hasUnreadMessages = _messages.any((msg) => 
            msg.senderId != _authService.currentUser?.uid && 
            msg.status == MessageStatus.delivered
          );
          if (hasUnreadMessages) {
            _messageService.markMessagesAsRead(_currentChatId!);
          }
        }
      }
    });

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _importPublicKeyIfNeeded(String userId) async {
    try {
      if (_encryptionService.hasPublicKey(userId)) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data()?['publicKey'] != null) {
        final publicKey = userDoc.data()!['publicKey'] as String;
        _encryptionService.importPublicKey(userId, publicKey);
        print('Public key imported for user $userId');
      } else {
        print('Public key not found for user $userId');
      }
    } catch (e) {
      print('Error importing public key: $e');
    }
  }

  String _generateChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_${userId2}'
        : '${userId2}_${userId1}';
  }

  void _loadMessages() {
    if (_currentChatId != null) {
      setState(() {
        _messages = _messageService.getMessages(_currentChatId!);
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _messageService.markMessagesAsRead(_currentChatId!);
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _otherUserId == null) {
      print(
        'Cannot send: text empty=${text.isEmpty}, otherUserId=$_otherUserId',
      );
      return;
    }

    _messageController.clear();

    await _importPublicKeyIfNeeded(_otherUserId!);

    try {
      print('Sending message to receiver: $_otherUserId');
      final isNewChat = await _messageService.sendMessage(
        receiverId: _otherUserId!,
        plainText: text,
        existingChatId: _currentChatId,
      );
      print('Message sent, isNewChat: $isNewChat');

      if (isNewChat && mounted) {
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6366F1 + Random().nextInt(100000)),
                    const Color(0xFF8B5CF6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  widget.userName.isNotEmpty ? widget.userName[0] : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _userStatusStream,
                builder: (context, snapshot) {
                  String status = 'offline';
                  String statusText = 'offline';
                  Color statusColor = Colors.grey;

                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                    if (userData != null) {
                      status = userData['status'] ?? 'offline';
                      if (status == 'online') {
                        statusText = 'online';
                        statusColor = Colors.green;
                      } else {
                        final lastSeen = (userData['lastSeen'] as Timestamp?)?.toDate();
                        if (lastSeen != null) {
                          final now = DateTime.now();
                          final diff = now.difference(lastSeen);
                          if (diff.inMinutes < 1) {
                            statusText = 'last seen just now';
                          } else if (diff.inMinutes < 60) {
                            statusText = 'last seen ${diff.inMinutes}m ago';
                          } else if (diff.inHours < 24) {
                            statusText = 'last seen ${diff.inHours}h ago';
                          } else {
                            statusText = 'last seen ${diff.inDays}d ago';
                          }
                        } else {
                          statusText = 'offline';
                        }
                      }
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.videocam_rounded),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.phone_rounded)),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.\nStart the conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe =
                          message.senderId == _authService.currentUser?.uid;

                      return _buildMessageBubble(context, message, isMe);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.attach_file_rounded),
                    color: theme.iconTheme.color,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(
                                  color: theme.iconTheme.color?.withOpacity(
                                    0.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.emoji_emotions_outlined),
                            color: theme.iconTheme.color,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    MessageModel message,
    bool isMe,
  ) {
    final theme = Theme.of(context);
    final showStatus = isMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : theme.colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    color: theme.iconTheme.color?.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
                if (showStatus) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

