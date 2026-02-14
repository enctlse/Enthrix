import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String text;
  final String? encryptedText;
  final DateTime timestamp;
  final String type;
  final String? fileUrl;
  final MessageStatus status;
  final DateTime? readAt;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.encryptedText,
    required this.timestamp,
    this.type = 'text',
    this.fileUrl,
    this.status = MessageStatus.sending,
    this.readAt,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] ?? '',
      chatId: map['chatId'] ?? '',
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      encryptedText: map['encryptedText'],
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: map['type'] ?? 'text',
      fileUrl: map['fileUrl'],
      status: _parseStatus(map['status']),
      readAt: (map['readAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'encryptedText': encryptedText,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'fileUrl': fileUrl,
      'status': status.toString().split('.').last,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
    };
  }

  Map<String, dynamic> toLocalStorageMap() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'encryptedText': encryptedText,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'fileUrl': fileUrl,
      'status': status.toString().split('.').last,
      'readAt': readAt?.toIso8601String(),
    };
  }

  factory MessageModel.fromLocalStorageMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] ?? '',
      chatId: map['chatId'] ?? '',
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      encryptedText: map['encryptedText'],
      timestamp: map['timestamp'] != null 
          ? DateTime.parse(map['timestamp']) 
          : DateTime.now(),
      type: map['type'] ?? 'text',
      fileUrl: map['fileUrl'],
      status: _parseStatus(map['status']),
      readAt: map['readAt'] != null ? DateTime.parse(map['readAt']) : null,
    );
  }

  Map<String, dynamic> toServerMap() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'encryptedText': encryptedText,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'fileUrl': fileUrl,
      'status': status.toString().split('.').last,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'delivered': false,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      ),
    };
  }

  static MessageStatus _parseStatus(String? status) {
    switch (status) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      case 'sending':
      default:
        return MessageStatus.sending;
    }
  }

  MessageModel copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? receiverId,
    String? text,
    String? encryptedText,
    DateTime? timestamp,
    String? type,
    String? fileUrl,
    MessageStatus? status,
    DateTime? readAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      encryptedText: encryptedText ?? this.encryptedText,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
    );
  }
}

