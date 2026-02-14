import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/message_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const EnthrixApp());
}

class EnthrixApp extends StatefulWidget {
  const EnthrixApp({super.key});

  @override
  State<EnthrixApp> createState() => _EnthrixAppState();
}

class _EnthrixAppState extends State<EnthrixApp> with WidgetsBindingObserver {
  bool _isDarkMode = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService.initializePresenceTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _authService.setAppBackground();
        break;
      case AppLifecycleState.resumed:
        messageService.ensureListening();
        _authService.setAppForeground();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enthrix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: StreamBuilder(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return HomeScreen(
              isDarkMode: _isDarkMode,
              onToggleTheme: _toggleTheme,
            );
          }

          return LoginScreen(
            isDarkMode: _isDarkMode,
            onToggleTheme: _toggleTheme,
          );
        },
      ),
    );
  }
}

