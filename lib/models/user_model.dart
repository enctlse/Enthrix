import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final String status;
  final DateTime lastSeen;
  final DateTime createdAt;
  final String? onionAddress;
  final List<String> pendingOnionRequests;
  final String? recoveryKeyHash; // Хеш ключа восстановления (не сам ключ!)

  UserModel({
    required this.uid,
    required this.name,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.status = 'offline',
    required this.lastSeen,
    required this.createdAt,
    this.onionAddress,
    this.pendingOnionRequests = const [],
    this.recoveryKeyHash,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      avatarUrl: map['avatarUrl'],
      bio: map['bio'],
      status: map['status'] ?? 'offline',
      lastSeen: (map['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      onionAddress: map['onionAddress'],
      pendingOnionRequests: List<String>.from(map['pendingOnionRequests'] ?? []),
      recoveryKeyHash: map['recoveryKeyHash'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'username': username,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'status': status,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'createdAt': Timestamp.fromDate(createdAt),
      'onionAddress': onionAddress,
      'pendingOnionRequests': pendingOnionRequests,
      'recoveryKeyHash': recoveryKeyHash,
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? username,
    String? avatarUrl,
    String? bio,
    String? status,
    DateTime? lastSeen,
    DateTime? createdAt,
    String? onionAddress,
    List<String>? pendingOnionRequests,
    String? recoveryKeyHash,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      onionAddress: onionAddress ?? this.onionAddress,
      pendingOnionRequests: pendingOnionRequests ?? this.pendingOnionRequests,
      recoveryKeyHash: recoveryKeyHash ?? this.recoveryKeyHash,
    );
  }
}
