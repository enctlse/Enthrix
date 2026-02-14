import 'package:flutter/material.dart';
import 'package:enthrix_messenger/screens/register_step_email.dart';

class RegisterScreen extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const RegisterScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return RegisterStepEmail(
      isDarkMode: isDarkMode,
      onToggleTheme: onToggleTheme,
    );
  }
}

