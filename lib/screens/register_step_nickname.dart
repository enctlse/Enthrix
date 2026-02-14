import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class RegisterStepNickname extends StatefulWidget {
  final String email;
  final String password;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const RegisterStepNickname({
    super.key,
    required this.email,
    required this.password,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<RegisterStepNickname> createState() => _RegisterStepNicknameState();
}

class _RegisterStepNicknameState extends State<RegisterStepNickname> {
  final _nicknameController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _isCreatingAccount = false;
  bool _isEmailVerified = false;
  bool _emailSent = false;
  String? _errorMessage;
  User? _createdUser;
  Timer? _verificationCheckTimer;

  @override
  void dispose() {
    _nicknameController.dispose();
    _verificationCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _createAccountAndSendVerification() async {
    if (_nicknameController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a nickname';
      });
      return;
    }

    setState(() {
      _isCreatingAccount = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.signUpWithEmailAndPassword(
        widget.email,
        widget.password,
        _nicknameController.text,
        '@${_nicknameController.text.toLowerCase().replaceAll(' ', '')}',
      );

      if (result != null) {
        _createdUser = _authService.currentUser;

        try {
          await _createdUser?.sendEmailVerification();
          print('Verification email sent successfully');
          setState(() {
            _emailSent = true;
          });

          _startVerificationCheck();
        } catch (e) {
          print('Failed to send verification email: $e');
          setState(() {
            _emailSent = true;
          });
          _startVerificationCheck();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isCreatingAccount = false;
      });
    }
  }

  void _startVerificationCheck() {
    _verificationCheckTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      await _checkEmailVerification();
    });
  }

  Future<void> _checkEmailVerification() async {
    if (_createdUser == null) return;

    try {
      await _createdUser!.reload();
      final user = _authService.currentUser;

      if (user != null && user.emailVerified) {
        _verificationCheckTimer?.cancel();
        setState(() {
          _isEmailVerified = true;
        });
      }
    } catch (e) {
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_createdUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _createdUser!.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent again')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to resend: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _completeRegistration() async {
    if (!_isEmailVerified) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.updateUserStatus('online');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              isDarkMode: widget.isDarkMode,
              onToggleTheme: widget.onToggleTheme,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('Almost Done!', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                'Step 3 of 3',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: 0.66,
                  minHeight: 8,
                  backgroundColor: theme.dividerTheme.color,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              if (!_emailSent) ...[
                Text('Choose your nickname', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'This is how others will see you',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      Icons.person_outline,
                      size: 50,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nicknameController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Your nickname',
                    hintStyle: TextStyle(
                      color: theme.iconTheme.color?.withOpacity(0.5),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'You can change this later in settings',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _isEmailVerified
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Icon(
                          _isEmailVerified
                              ? Icons.check_circle_outline
                              : Icons.mark_email_unread_outlined,
                          size: 60,
                          color: _isEmailVerified
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _isEmailVerified
                            ? 'Email Verified!'
                            : 'Verify Your Email',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'We\'ve sent a verification link to:',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.email,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _isEmailVerified
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isEmailVerified
                                ? Colors.green.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isEmailVerified
                                  ? Icons.check_circle
                                  : Icons.access_time,
                              color: _isEmailVerified
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isEmailVerified
                                  ? 'Verified'
                                  : 'Waiting for verification...',
                              style: TextStyle(
                                color: _isEmailVerified
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isEmailVerified) ...[
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: _resendVerificationEmail,
                          child: const Text('Resend verification email'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              if (!_emailSent) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isCreatingAccount
                        ? null
                        : _createAccountAndSendVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isCreatingAccount
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Create Account & Send Verification',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isEmailVerified && !_isLoading
                        ? _completeRegistration
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isEmailVerified
                          ? theme.colorScheme.primary
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isEmailVerified
                                ? 'Get Started'
                                : 'Waiting for verification...',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

