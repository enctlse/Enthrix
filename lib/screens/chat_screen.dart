import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/encryption_service.dart';
import '../services/settings_service.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'user_profile_screen.dart';

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
  final _searchController = TextEditingController();
  final _authService = AuthService();
  final _messageService = messageService;
  final _encryptionService = EncryptionService();
  final _firestore = FirebaseFirestore.instance;
  final _settingsService = SettingsService();

  String? _currentChatId;
  String? _otherUserId;
  bool _isLoading = true;
  List<MessageModel> _messages = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingStatusSubscription;
  Stream<DocumentSnapshot>? _userStatusStream;
  late ChatCustomization _chatCustomization;
  late String _displayName;

  // Reply functionality
  MessageModel? _replyingTo;

  // Search functionality
  bool _isSearching = false;
  List<MessageModel> _searchResults = [];

  // Typing status
  bool _isTyping = false;
  bool _otherUserTyping = false;
  Timer? _typingTimer;

  // Self-destruct timer
  int? _selectedSelfDestructTime;
  final List<int> _selfDestructOptions = [0, 5, 10, 30, 60, 300, 3600]; // 0 = off, 5s, 10s, 30s, 1m, 5m, 1h

  // Stickers
  bool _showStickers = false;
  final List<String> _stickers = ['😀', '😂', '🥰', '😎', '🤔', '👍', '❤️', '🎉', '🔥', '👏', '😭', '😡'];

  @override
  void initState() {
    super.initState();
    _chatCustomization = _settingsService.chatCustomization;
    _displayName = _getDisplayName();
    _initializeChat();
  }

  String _getDisplayName() {
    if (widget.otherUserId != null) {
      final customName = _settingsService.getContactName(widget.otherUserId!);
      if (customName != null && customName.isNotEmpty) {
        return customName;
      }
    }
    return widget.userName;
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

    // Listen for messages
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
          
          // Start self-destruct timers for read messages
          for (final msg in _messages) {
            if (msg.selfDestructSeconds != null && 
                msg.status == MessageStatus.read && 
                !msg.isDeleted) {
              _messageService.startSelfDestructTimer(_currentChatId!, msg);
            }
          }
        }
      }
    });

    // Listen for typing status
    if (_currentChatId != null) {
      _typingStatusSubscription = _messageService.typingStatusStream.listen((statusMap) {
        if (mounted) {
          setState(() {
            _otherUserTyping = statusMap[_currentChatId] ?? false;
          });
        }
      });
      _messageService.startListeningForTypingStatus(
        _currentChatId!, 
        _authService.currentUser!.uid,
      );
    }

    // Listen for delete signals
    if (_authService.currentUser != null) {
      _messageService.startListeningForDeleteSignals(_authService.currentUser!.uid);
    }

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
      return;
    }

    _messageController.clear();
    _cancelReply();
    _showStickers = false;

    await _importPublicKeyIfNeeded(_otherUserId!);

    try {
      final isNewChat = await _messageService.sendMessage(
        receiverId: _otherUserId!,
        plainText: text,
        existingChatId: _currentChatId,
        selfDestructSeconds: _selectedSelfDestructTime != null && _selectedSelfDestructTime! > 0 
            ? _selectedSelfDestructTime 
            : null,
        replyToMessageId: _replyingTo?.id,
        replyToText: _replyingTo?.text,
      );

      _cancelReply();

      if (isNewChat && mounted) {
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  Future<void> _sendSticker(String sticker) async {
    if (_otherUserId == null) return;

    setState(() {
      _showStickers = false;
    });

    await _importPublicKeyIfNeeded(_otherUserId!);

    try {
      await _messageService.sendMessage(
        receiverId: _otherUserId!,
        plainText: sticker,
        existingChatId: _currentChatId,
        replyToMessageId: _replyingTo?.id,
        replyToText: _replyingTo?.text,
        type: 'sticker',
      );
      _cancelReply();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  void _onTextChanged(String text) {
    if (!_isTyping && text.isNotEmpty) {
      _isTyping = true;
      if (_currentChatId != null) {
        _messageService.setTypingStatus(_currentChatId!, true);
      }
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_isTyping) {
        _isTyping = false;
        if (_currentChatId != null) {
          _messageService.setTypingStatus(_currentChatId!, false);
        }
      }
    });
  }

  void _startReply(MessageModel message) {
    if (mounted) {
      setState(() {
        _replyingTo = message;
      });
    }
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchResults = [];
      }
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    if (_currentChatId != null) {
      setState(() {
        _searchResults = _messageService.searchMessages(_currentChatId!, query);
      });
    }
  }

  void _deleteMessageForEveryone(MessageModel message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Delete this message for everyone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_currentChatId != null) {
                await _messageService.deleteMessageForEveryone(_currentChatId!, message.id);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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

  Widget _buildBackgroundPattern() {
    switch (_chatCustomization.patternType) {
      case 'dots':
        return CustomPaint(
          size: Size.infinite,
          painter: DotsPatternPainter(color: Colors.black.withOpacity(0.05)),
        );
      case 'grid':
        return CustomPaint(
          size: Size.infinite,
          painter: GridPatternPainter(color: Colors.black.withOpacity(0.05)),
        );
      case 'waves':
        return CustomPaint(
          size: Size.infinite,
          painter: WavesPatternPainter(color: Colors.black.withOpacity(0.05)),
        );
      case 'hearts':
        return CustomPaint(
          size: Size.infinite,
          painter: HeartsPatternPainter(color: Colors.black.withOpacity(0.05)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _messageSubscription?.cancel();
    _typingStatusSubscription?.cancel();
    _typingTimer?.cancel();
    _messageService.stopListeningForTypingStatus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Обновляем настройки при каждой перестройке
    _chatCustomization = _settingsService.chatCustomization;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      appBar: _isSearching 
        ? AppBar(
            leading: IconButton(
              onPressed: _toggleSearch,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search messages...',
                border: InputBorder.none,
              ),
              onChanged: _performSearch,
            ),
          )
        : AppBar(
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
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _displayName.isNotEmpty ? _displayName[0] : '?',
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
                          if (_otherUserTyping) {
                            statusText = 'typing...';
                            statusColor = Colors.green;
                          } else if (status == 'online') {
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

                      return GestureDetector(
                        onTap: () {
                          if (widget.otherUserId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(
                                  userId: widget.otherUserId!,
                                  userName: _displayName,
                                ),
                              ),
                            );
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
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
                        ),
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'search') {
                    _toggleSearch();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        Icon(Icons.search),
                        SizedBox(width: 8),
                        Text('Search'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
      body: Column(
        children: [
          // Search results indicator
          if (_isSearching && _searchResults.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.primary.withOpacity(0.1),
              child: Text(
                '${_searchResults.length} messages found',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _chatCustomization.backgroundColor,
              ),
              child: Stack(
                children: [
                  if (_chatCustomization.patternType != null)
                    _buildBackgroundPattern(),
                  
                  // Messages list
                  _isSearching
                      ? _searchResults.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages found',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final message = _searchResults[index];
                                final isMe = message.senderId == _authService.currentUser?.uid;
                                return _buildMessageBubble(context, message, isMe, index);
                              },
                            )
                      : _messages.isEmpty
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
                                final isMe = message.senderId == _authService.currentUser?.uid;
                                final isLastMessage = index == _messages.length - 1;
                                
                                // Animate only the last (newest) message
                                if (isLastMessage) {
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, child) {
                                      return Transform.translate(
                                        offset: Offset(0, 20 * (1 - value)),
                                        child: Opacity(
                                          opacity: value,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _buildMessageBubble(context, message, isMe, index),
                                  );
                                }
                                
                                return _buildMessageBubble(context, message, isMe, index);
                              },
                            ),
                ],
              ),
            ),
          ),
          
          // Reply preview
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.dividerTheme.color!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyingTo!.senderId == _authService.currentUser?.uid
                              ? 'You'
                              : _displayName,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _cancelReply,
                    icon: const Icon(Icons.close, size: 20),
                    color: theme.iconTheme.color,
                  ),
                ],
              ),
            ),
          
          // Stickers panel
          if (_showStickers)
            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.dividerTheme.color!),
                ),
              ),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _stickers.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _sendSticker(_stickers[index]),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _stickers[index],
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          
          // Message input
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Self-destruct timer selector
                  if (_selectedSelfDestructTime != null && _selectedSelfDestructTime! > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer,
                            size: 16,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatSelfDestructTime(_selectedSelfDestructTime!),
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _selectedSelfDestructTime = 0),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  Row(
                    children: [
                      // Self-destruct button
                      PopupMenuButton<int>(
                        icon: Icon(
                          _selectedSelfDestructTime != null && _selectedSelfDestructTime! > 0
                              ? Icons.timer
                              : Icons.timer_outlined,
                          color: _selectedSelfDestructTime != null && _selectedSelfDestructTime! > 0
                              ? Colors.orange
                              : theme.iconTheme.color,
                        ),
                        onSelected: (value) {
                          setState(() {
                            _selectedSelfDestructTime = value;
                          });
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Text('Off'),
                          ),
                          const PopupMenuItem(
                            value: 5,
                            child: Text('5 seconds'),
                          ),
                          const PopupMenuItem(
                            value: 10,
                            child: Text('10 seconds'),
                          ),
                          const PopupMenuItem(
                            value: 30,
                            child: Text('30 seconds'),
                          ),
                          const PopupMenuItem(
                            value: 60,
                            child: Text('1 minute'),
                          ),
                          const PopupMenuItem(
                            value: 300,
                            child: Text('5 minutes'),
                          ),
                          const PopupMenuItem(
                            value: 3600,
                            child: Text('1 hour'),
                          ),
                        ],
                      ),
                      
                      // Attach button
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.attach_file_rounded),
                        color: theme.iconTheme.color,
                      ),
                      
                      // Text field
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
                                      color: theme.iconTheme.color?.withOpacity(0.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: _onTextChanged,
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _showStickers = !_showStickers;
                                  });
                                },
                                icon: Icon(
                                  _showStickers 
                                      ? Icons.keyboard 
                                      : Icons.emoji_emotions_outlined,
                                ),
                                color: theme.iconTheme.color,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Send button
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSelfDestructTime(int seconds) {
    if (seconds < 60) return '$seconds sec';
    if (seconds < 3600) return '${seconds ~/ 60} min';
    return '${seconds ~/ 3600} hour';
  }

  Widget _buildMessageBubble(
    BuildContext context,
    MessageModel message,
    bool isMe,
    int index,
  ) {
    final theme = Theme.of(context);
    final showStatus = isMe;
    final isSticker = message.type == 'sticker';

    // Message bubble with tap and long press
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe to reply - detect horizontal swipe
        if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 100) {
          _startReply(message);
        }
      },
      onLongPress: () {
        _showMessageOptions(context, message, isMe);
      },
      child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Reply preview
                if (message.replyToMessageId != null && message.replyToMessageId!.isNotEmpty && !message.isDeleted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withOpacity(0.2)
                          : theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message.replyToText ?? 'Reply to message',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withOpacity(0.8)
                            : theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                
                // Message bubble
                Container(
                  padding: isSticker
                      ? const EdgeInsets.all(8)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: message.isDeleted
                        ? Colors.grey.withOpacity(0.3)
                        : isMe
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(_chatCustomization.borderRadius),
                      topRight: Radius.circular(_chatCustomization.borderRadius),
                      bottomLeft: Radius.circular(isMe ? _chatCustomization.borderRadius : 4),
                      bottomRight: Radius.circular(isMe ? 4 : _chatCustomization.borderRadius),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isSticker)
                        Text(
                          message.text,
                          style: const TextStyle(fontSize: 48),
                        )
                      else
                        Text(
                          message.text,
                          style: TextStyle(
                            color: isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                            fontSize: _chatCustomization.messageTextSize,
                            height: 1.3,
                          ),
                        ),
                      
                      // Self-destruct indicator
                      if (message.selfDestructSeconds != null && !message.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer,
                                size: 12,
                                color: isMe ? Colors.white70 : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatSelfDestructTime(message.selfDestructSeconds!),
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.orange,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 4),
                
                // Timestamp and status
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
                    if (showStatus && !message.isDeleted) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(message.status),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

    );
  }

  void _showMessageOptions(BuildContext context, MessageModel message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _startReply(message);
              },
            ),
            if (isMe && !message.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete for everyone', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessageForEveryone(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                // Copy to clipboard
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DotsPatternPainter extends CustomPainter {
  final Color color;

  DotsPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GridPatternPainter extends CustomPainter {
  final Color color;

  GridPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 30.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WavesPatternPainter extends CustomPainter {
  final Color color;

  WavesPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    for (double y = 0; y < size.height; y += spacing) {
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 20) {
        path.quadraticBezierTo(
          x + 10, y + 10,
          x + 20, y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HeartsPatternPainter extends CustomPainter {
  final Color color;

  HeartsPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    const spacing = 50.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        _drawHeart(canvas, Offset(x + 10, y + 10), 6, paint);
      }
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy + size * 0.3);
    path.cubicTo(
      center.dx - size * 0.5, center.dy - size * 0.3,
      center.dx - size, center.dy + size * 0.1,
      center.dx, center.dy + size,
    );
    path.cubicTo(
      center.dx + size, center.dy + size * 0.1,
      center.dx + size * 0.5, center.dy - size * 0.3,
      center.dx, center.dy + size * 0.3,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

