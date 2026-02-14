import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'message_service.dart';
import 'encryption_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  GoogleSignIn? _googleSignIn;
  Timer? _statusUpdateTimer;
  StreamSubscription? _authSubscription;

  GoogleSignIn get _googleSignInInstance {
    _googleSignIn ??= GoogleSignIn();
    return _googleSignIn!;
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserModel?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
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

  Future<UserModel?> signUpWithEmailAndPassword(
    String email,
    String password,
    String name,
    String username,
  ) async {
    try {
      if (!_isValidEmail(email)) {
        throw 'Invalid email address format.';
      }

      if (password.length < 6) {
        throw 'Password must be at least 6 characters long.';
      }

      print('Creating user with email: $email');

      try {
        final methods = await _auth.fetchSignInMethodsForEmail(email.trim());
        if (methods.isNotEmpty) {
          throw 'Email is already registered.';
        }
      } catch (e) {
        if (e is String && e.contains('already registered')) {
          rethrow;
        }
      }

      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (result.user != null) {
        print('User created: ${result.user!.uid}');

        try {
          await result.user!.sendEmailVerification();
          print('Verification email sent');
        } catch (e) {
          print('Failed to send verification email: $e');
        }

        final userModel = UserModel(
          uid: result.user!.uid,
          email: email.trim(),
          name: name,
          username: username,
          status: 'online',
          lastSeen: DateTime.now(),
          createdAt: DateTime.now(),
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toMap());
        print('User data saved to Firestore');

        try {
          await EncryptionService().initialize(result.user!.uid);
          final publicKey = EncryptionService().getPublicKeyString();
          await _firestore.collection('users').doc(result.user!.uid).update({
            'publicKey': publicKey,
          });
          print('Public key saved to Firestore');
        } catch (e) {
          print('Failed to save public key: $e');
        }

        return userModel;
      }
      return null;
    } catch (e) {
      print('SignUp Error: $e');
      throw _handleAuthError(e);
    }
  }

  bool _isValidEmail(String email) {
    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegExp.hasMatch(email);
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return user.emailVerified;
    }
    return false;
  }

  Future<void> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignInInstance.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);

      if (result.user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .get();

        if (!userDoc.exists) {
          final userModel = UserModel(
            uid: result.user!.uid,
            email: result.user!.email!,
            name: result.user!.displayName ?? 'User',
            username: '@${result.user!.email!.split('@')[0]}',
            avatarUrl: result.user!.photoURL,
            status: 'online',
            lastSeen: DateTime.now(),
            createdAt: DateTime.now(),
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

          return userModel;
        }

        try {
          await EncryptionService().initialize(result.user!.uid);
          final publicKey = EncryptionService().getPublicKeyString();
          await _firestore.collection('users').doc(result.user!.uid).update({
            'publicKey': publicKey,
          });
        } catch (e) {
          print('Failed to initialize encryption: $e');
        }

        return UserModel.fromMap(userDoc.data()!);
      }
      return null;
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('ClientID') || errorMsg.contains('client_id') || errorMsg.contains('google-signin-client_id')) {
        throw 'Google Sign-In is not configured for web. Please use email/password sign-in instead.';
      }
      throw _handleAuthError(e);
    }
  }

  Future<void> signOut() async {
    await _setOffline();
    _stopPeriodicStatusUpdate();
    
    messageService.clear();
    
    await _googleSignInInstance.signOut();
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
          return 'No user found with this email.';
        case 'wrong-password':
          return 'Wrong password provided.';
        case 'email-already-in-use':
          return 'Email is already registered.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'invalid-email':
          return 'Invalid email address.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'invalid-credential':
          return 'Invalid email or password.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is not enabled. Please contact support.';
        default:
          return 'Authentication error (${error.code}): ${error.message}';
      }
    }

    final errorStr = error.toString();
    if (errorStr.contains('PigeonUserDetails') ||
        errorStr.contains('type') && errorStr.contains('is not a subtype')) {
      print('Internal Firebase error: $errorStr');
      return 'Authentication service error. Please try again.';
    }

    if (error is String) {
      return error;
    }
    return 'Error: $error';
  }
}

