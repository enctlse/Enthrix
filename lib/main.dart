import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:secure_application/secure_application.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/message_service.dart';
import 'services/settings_service.dart';
import 'services/tor_service.dart';
import 'services/connectivity_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final settingsService = SettingsService();
  await settingsService.initialize();

  // Initialize Tor service if enabled
  if (settingsService.isTorEnabled) {
    final torService = TorService();
    await torService.initialize(enabled: true);
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: settingsService.isDarkMode ? Brightness.light : Brightness.dark,
    ),
  );

  runApp(EnthrixApp(settingsService: settingsService));
}

class EnthrixApp extends StatefulWidget {
  final SettingsService settingsService;

  const EnthrixApp({super.key, required this.settingsService});

  @override
  State<EnthrixApp> createState() => _EnthrixAppState();
}

class _EnthrixAppState extends State<EnthrixApp> with WidgetsBindingObserver {
  late bool _isDarkMode;
  final AuthService _authService = AuthService();
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isDarkMode = widget.settingsService.isDarkMode;
    _authService.initializePresenceTracking();
    _connectivityService.startMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.dispose();
    _connectivityService.stopMonitoring();
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
    widget.settingsService.setDarkMode(_isDarkMode);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isDarkMode ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecureApplication(
      nativeRemoveDelay: 500,
      onNeedUnlock: (secure) async {
        // Return null to automatically unlock, or SUCCESS/FAILED for custom auth
        return null;
      },
      child: MaterialApp(
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
              return SecureGate(
                child: HomeScreen(
                  isDarkMode: _isDarkMode,
                  onToggleTheme: _toggleTheme,
                ),
              );
            }

            return SecureGate(
              child: LoginScreen(
                isDarkMode: _isDarkMode,
                onToggleTheme: _toggleTheme,
              ),
            );
          },
        ),
      ),
    );
  }
}

