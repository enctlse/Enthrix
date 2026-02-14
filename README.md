# Enthrix Messenger

A modern, secure Flutter messenger application with end-to-end encryption.

## Features

### Core Features
- **End-to-End Encryption**: All messages are encrypted using RSA + AES encryption
- **Real-time Messaging**: Instant message delivery using Firebase Firestore
- **User Authentication**: Email/password and Google Sign-In support
- **Chat History**: Messages are stored locally on device
- **Online Status**: See when users are online/offline
- **Read Receipts**: Know when your messages are read
- **Dark/Light Theme**: Support for both themes

### Security Features
- RSA 2048-bit key pairs for encryption
- AES encryption for message content
- Private keys stored securely in device storage
- Ephemeral messages (deleted from server after delivery)

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── firebase_options.dart     # Firebase configuration
├── models/                   # Data models
│   ├── message_model.dart    # Message model
│   └── user_model.dart       # User model
├── screens/                  # UI screens
│   ├── home_screen.dart      # Main chat list screen
│   ├── chat_screen.dart      # Individual chat screen
│   ├── login_screen.dart     # Login screen
│   ├── register_screen.dart  # Registration screen
│   ├── profile_screen.dart   # User profile screen
│   ├── search_screen.dart    # User search screen
│   └── settings_screen.dart  # App settings screen
├── services/                 # Business logic
│   ├── auth_service.dart     # Authentication service
│   ├── message_service.dart  # Messaging service
│   └── encryption_service.dart # Encryption service
├── theme/                    # App theming
│   └── app_theme.dart        # Theme definitions
└── widgets/                  # Reusable widgets
    └── app_drawer.dart       # Navigation drawer
```

## Architecture

### Authentication Flow
1. User signs in via email/password or Google
2. AuthService creates/updates user in Firestore
3. EncryptionService initializes with user's RSA key pair
4. Public key is stored in Firestore for other users

### Messaging Flow

#### Sending a Message
1. User composes message in ChatScreen
2. MessageService retrieves recipient's public key
3. Message is encrypted using AES with random key
4. AES key is encrypted with recipient's RSA public key
5. Encrypted message is sent to Firestore
6. Local copy is saved with "sent" status

#### Receiving a Message
1. Firestore listener detects new message
2. MessageService decrypts AES key using private key
3. Message content is decrypted using AES key
4. Message is stored locally with "delivered" status
5. Read receipt is sent back to sender
6. Message is marked for deletion on server

### Data Storage

#### Local Storage (SharedPreferences)
- User's RSA private key (secure storage)
- Chat history (messages)
- Active chats list

#### Firebase Firestore
- User profiles (uid, name, email, username, publicKey, status)
- Incoming messages (ephemeral, deleted after delivery)
- Read receipts (ephemeral)

## Setup Instructions

### Prerequisites
- Flutter SDK ^3.10.8
- Firebase project
- Android Studio / VS Code

### Firebase Setup
1. Create Firebase project at https://console.firebase.google.com
2. Add Android app with package name: `com.example.enthrix_messenger`
3. Download `google-services.json` and place in `android/app/`
4. Add iOS app if needed
5. Enable Authentication (Email/Password and Google)
6. Enable Firestore Database

### Installation

```bash
# Clone repository
git clone <repository-url>
cd enthrix_messenger

# Install dependencies
flutter pub get

# Generate app icons
flutter pub run flutter_launcher_icons

# Build APK
flutter build apk --release
```

### Configuration

#### App Name
Edit `android/app/src/main/AndroidManifest.xml`:
```xml
android:label="Enthrix"
```

#### App Icon
Place your icon as `icon.png` in project root, then run:
```bash
flutter pub run flutter_launcher_icons
```

## Security Considerations

### Key Management
- Private keys are generated once and stored securely
- Keys survive app reinstalls (if backup enabled)
- Each device has unique key pair

### Message Security
- Messages are encrypted end-to-end
- Server never sees plaintext
- Messages deleted from server after delivery
- No message history stored on server

### Known Limitations
- Multi-device support requires key synchronization
- No cloud backup of chat history
- Device loss = loss of private key and message history

## API Reference

### AuthService
- `signInWithEmailAndPassword(email, password)` - Email login
- `signInWithGoogle()` - Google login
- `signOut()` - Sign out
- `getUserData(uid)` - Get user profile
- `updateUserProfile(...)` - Update profile

### MessageService
- `initialize()` - Initialize messaging
- `sendMessage(receiverId, text)` - Send encrypted message
- `getMessages(chatId)` - Get chat messages
- `getUserChats(userId)` - Get user's chats
- `markMessagesAsRead(chatId)` - Mark as read

### EncryptionService
- `initialize(userId)` - Setup encryption keys
- `getPublicKeyString()` - Get public key for sharing
- `encryptMessage(plainText, receiverId)` - Encrypt message
- `decryptMessage(encryptedData)` - Decrypt message

## UI Components

### HomeScreen
- Chat list with last message preview
- Online status indicator
- Pull-to-refresh
- Floating action button for new chat

### ChatScreen
- Message bubbles (sent/received)
- Encryption indicator
- Read receipts (checkmarks)
- Typing indicator
- Online status in app bar

### ProfileScreen
- User avatar and info
- Editable username and bio
- About section with email
- Settings button

### SettingsScreen
- Dark mode toggle
- Online status toggle
- Read receipts toggle
- Log out button

## Theming

### Colors
- Primary: #6366F1 (Indigo)
- Secondary: #8B5CF6 (Purple)
- Success: Green (online status)
- Error: Red (failed messages)

### Typography
- Font: Inter
- Sizes: 12-24sp range
- Weights: 400-700

## Testing

```bash
# Run unit tests
flutter test

# Run on device
flutter run

# Build release APK
flutter build apk --release

# Build app bundle
flutter build appbundle
```

## Deployment

### Android
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS
```bash
flutter build ios --release
# Open in Xcode and deploy
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## License

MIT License - see LICENSE file

## Support

For support, email support@enthrix.app or join our Discord.

## Roadmap

- [ ] Group chats
- [ ] Channels
- [ ] Voice messages
- [ ] File sharing
- [ ] Video calls
- [ ] Desktop app
- [ ] Multi-device sync
- [ ] Cloud backup

---

Built with Flutter and Firebase
