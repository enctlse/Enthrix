import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';
import 'message_service.dart';
import 'encryption_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _statusUpdateTimer;
  StreamSubscription? _authSubscription;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // Generate fake email from username for Firebase Auth
  String _generateEmail(String username) {
    return '${username.toLowerCase().replaceAll(' ', '_')}@enthrix.local';
  }

  // Generate recovery key
  String generateRecoveryKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).substring(0, 24).toUpperCase();
  }

  // Hash recovery key for storage
  String _hashRecoveryKey(String recoveryKey) {
    final bytes = utf8.encode(recoveryKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<UserModel?> signInWithUsernameAndPassword(
    String username,
    String password,
  ) async {
    try {
      final email = _generateEmail(username);
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        try {
          await EncryptionService().initialize(result.user!.uid);
          final publicKey = EncryptionService().getPublicKeyString();
          await _firestore.collection('users').doc(result.user!.uid).update({
            'publicKey': publicKey,
          });
        } catch (e) {
          print('Failed to initialize encryption: $e');
        }
        return await getUserData(result.user!.uid);
      }
      return null;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<Map<String, dynamic>> signUpWithUsernameAndPassword(
    String username,
    String password,
  ) async {
    try {
      if (username.length < 3) {
        throw 'Username must be at least 3 characters long.';
      }

      if (password.length < 6) {
        throw 'Password must be at least 6 characters long.';
      }

      final email = _generateEmail(username);
      
      // Check if email is already registered
      try {
        final methods = await _auth.fetchSignInMethodsForEmail(email);
        if (methods.isNotEmpty) {
          throw 'Username is already taken.';
        }
      } catch (e) {
        if (e is String && e.contains('already taken')) {
          rethrow;
        }
      }

      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Wait for auth token to be ready
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Generate recovery key
        final recoveryKey = generateRecoveryKey();
        final recoveryKeyHash = _hashRecoveryKey(recoveryKey);

        final userModel = UserModel(
          uid: result.user!.uid,
          name: username,
          username: username.toLowerCase(),
          status: 'online',
          lastSeen: DateTime.now(),
          createdAt: DateTime.now(),
          recoveryKeyHash: recoveryKeyHash,
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toMap());

        try {
          await EncryptionService().initialize(result.user!.uid);
          final publicKey = EncryptionService().getPublicKeyString();
          await _firestore.collection('users').doc(result.user!.uid).update({
            'publicKey': publicKey,
          });
        } catch (e) {
          print('Failed to save public key: $e');
        }

        return {
          'user': userModel,
          'recoveryKey': recoveryKey,
        };
      }
      return {};
    } catch (e) {
      print('SignUp Error: $e');
      throw _handleAuthError(e);
    }
  }

  // Recover account with recovery key
  Future<Map<String, dynamic>?> recoverAccount(
    String username,
    String recoveryKey,
  ) async {
    try {
      // Find user by username
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.toLowerCase())
          .get();
      
      if (usernameQuery.docs.isEmpty) {
        throw 'User not found.';
      }

      final userData = usernameQuery.docs.first.data();
      final storedHash = userData['recoveryKeyHash'] as String?;
      
      if (storedHash == null) {
        throw 'Recovery key not set for this account.';
      }

      // Verify recovery key
      final providedHash = _hashRecoveryKey(recoveryKey);
      if (providedHash != storedHash) {
        throw 'Invalid recovery key.';
      }

      return {
        'uid': userData['uid'],
        'username': userData['username'],
        'name': userData['name'],
      };
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Reset password after recovery
  Future<void> resetPasswordWithRecovery(
    String username,
    String recoveryKey,
    String newPassword,
  ) async {
    try {
      if (newPassword.length < 6) {
        throw 'Password must be at least 6 characters long.';
      }

      // Verify recovery key first
      final userInfo = await recoverAccount(username, recoveryKey);
      if (userInfo == null) {
        throw 'Recovery failed.';
      }

      // Generate new recovery key
      final newRecoveryKey = generateRecoveryKey();
      final newRecoveryKeyHash = _hashRecoveryKey(newRecoveryKey);

      // We need to sign in as admin to change password - for now, user needs to know old password
      // Or we can implement custom logic
      // For simplicity, we'll update the recovery key and inform user to contact support
      
      await _firestore.collection('users').doc(userInfo['uid']).update({
        'recoveryKeyHash': newRecoveryKeyHash,
      });

      // Note: In production, you'd need a cloud function or admin SDK to reset password
      // without knowing the old one. For now, we'll inform the user.
      throw 'Password reset requires re-authentication. Please contact support or use the app settings if logged in.';
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<void> signOut() async {
    await _setOffline();
    _stopPeriodicStatusUpdate();
    
    messageService.clear();
    
    await _auth.signOut();
  }

  Future<void> deleteCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.delete();
    }
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.toLowerCase())
          .get();
      
      if (query.docs.isNotEmpty) {
        return UserModel.fromMap(query.docs.first.data());
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateUserStatus(String status) async {
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'status': status,
        'lastSeen': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  void initializePresenceTracking() {
    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        _setOnline();
        _startPeriodicStatusUpdate();
        messageService.initialize();
      } else {
        _setOffline();
        _stopPeriodicStatusUpdate();
        messageService.stopListening();
      }
    });
  }

  Future<void> _setOnline() async {
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'status': 'online',
        'lastSeen': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  Future<void> _setOffline() async {
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'status': 'offline',
        'lastSeen': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  void _startPeriodicStatusUpdate() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _setOnline();
    });
  }

  void _stopPeriodicStatusUpdate() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = null;
  }

  Future<void> setAppBackground() async {
    await _setOffline();
    _stopPeriodicStatusUpdate();
  }

  Future<void> setAppForeground() async {
    await _setOnline();
    _startPeriodicStatusUpdate();

    if (currentUser != null) {
      messageService.initialize();
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _stopPeriodicStatusUpdate();
    messageService.dispose();
  }

  Future<void> updateUserProfile({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    if (currentUser != null) {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (username != null) updates['username'] = username;
      if (bio != null) updates['bio'] = bio;
      if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;

      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .update(updates);
    }
  }

  String _handleAuthError(dynamic error) {
    if (error is FirebaseAuthException) {
      print(
        'FirebaseAuthException code: ${error.code}, message: ${error.message}',
      );
      switch (error.code) {
        case 'user-not-found':
          return 'Invalid username or password.';
        case 'wrong-password':
          return 'Invalid username or password.';
        case 'email-already-in-use':
          return 'Username is already taken.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'invalid-email':
          return 'Invalid username format.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'invalid-credential':
          return 'Invalid username or password.';
        default:
          return 'Authentication error: ${error.message}';
      }
    }

    if (error is String) {
      return error;
    }
    return 'Error: $error';
  }
}
