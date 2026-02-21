import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatCustomization {
  final double borderRadius;
  final Color backgroundColor;
  final String? patternType;
  final double messageTextSize;

  const ChatCustomization({
    this.borderRadius = 16.0,
    this.backgroundColor = const Color(0xFFE8F5E9),
    this.patternType,
    this.messageTextSize = 16.0,
  });

  ChatCustomization copyWith({
    double? borderRadius,
    Color? backgroundColor,
    String? patternType,
    double? messageTextSize,
  }) {
    return ChatCustomization(
      borderRadius: borderRadius ?? this.borderRadius,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      patternType: patternType ?? this.patternType,
      messageTextSize: messageTextSize ?? this.messageTextSize,
    );
  }
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _darkModeKey = 'isDarkMode';
  static const String _chatBorderRadiusKey = 'chatBorderRadius';
  static const String _chatBackgroundColorKey = 'chatBackgroundColor';
  static const String _chatPatternTypeKey = 'chatPatternType';
  static const String _chatMessageTextSizeKey = 'chatMessageTextSize';
  static const String _torEnabledKey = 'torEnabled';

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get isDarkMode => _prefs?.getBool(_darkModeKey) ?? false;

  Future<void> setDarkMode(bool value) async {
    await _prefs?.setBool(_darkModeKey, value);
  }

  ChatCustomization get chatCustomization {
    return ChatCustomization(
      borderRadius: _prefs?.getDouble(_chatBorderRadiusKey) ?? 16.0,
      backgroundColor: Color(_prefs?.getInt(_chatBackgroundColorKey) ?? 0xFFE8F5E9),
      patternType: _prefs?.getString(_chatPatternTypeKey),
      messageTextSize: _prefs?.getDouble(_chatMessageTextSizeKey) ?? 16.0,
    );
  }

  Future<void> setChatCustomization(ChatCustomization customization) async {
    await _prefs?.setDouble(_chatBorderRadiusKey, customization.borderRadius);
    await _prefs?.setInt(_chatBackgroundColorKey, customization.backgroundColor.value);
    if (customization.patternType != null) {
      await _prefs?.setString(_chatPatternTypeKey, customization.patternType!);
    } else {
      await _prefs?.remove(_chatPatternTypeKey);
    }
    await _prefs?.setDouble(_chatMessageTextSizeKey, customization.messageTextSize);
  }

  // Tor settings
  bool get isTorEnabled => _prefs?.getBool(_torEnabledKey) ?? false;

  Future<void> setTorEnabled(bool value) async {
    await _prefs?.setBool(_torEnabledKey, value);
  }

  // Contact names
  String? getContactName(String userId) {
    return _prefs?.getString('contact_name_$userId');
  }

  Future<void> setContactName(String userId, String name) async {
    await _prefs?.setString('contact_name_$userId', name);
  }
}
