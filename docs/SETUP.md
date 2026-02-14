# Setup Guide

## Prerequisites

Before starting, ensure you have:

1. **Flutter SDK** (version ^3.10.8)
   ```bash
   flutter --version
   ```

2. **Android Studio** or **VS Code** with Flutter extension

3. **Firebase Account** (free tier sufficient)

4. **Git** for version control

## Installation Steps

### 1. Clone Repository

```bash
git clone <repository-url>
cd enthrix_messenger
```

### 2. Install Dependencies

```bash
flutter pub get
```

This installs all required packages including:
- firebase_core
- firebase_auth
- cloud_firestore
- flutter_secure_storage
- encrypt
- pointycastle
- And others...

### 3. Firebase Setup

#### Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Create Project"
3. Name it "Enthrix Messenger"
4. Disable Google Analytics (optional)
5. Click "Create"

#### Add Android App

1. In Firebase Console, click Android icon
2. Package name: `com.example.enthrix_messenger`
3. App nickname: "Enthrix"
4. Debug signing certificate (optional for development)
5. Click "Register"
6. Download `google-services.json`
7. Move file to: `android/app/google-services.json`

#### Add iOS App (Optional)

1. In Firebase Console, click iOS icon
2. Bundle ID: `com.example.enthrixMessenger`
3. Download `GoogleService-Info.plist`
4. Move file to: `ios/Runner/GoogleService-Info.plist`

#### Enable Services

1. Go to **Authentication** → **Sign-in method**
2. Enable:
   - Email/Password
   - Google (add SHA-1 fingerprint)

3. Go to **Firestore Database** → **Create database**
4. Start in **test mode** (for development)
5. Choose location closest to your users

### 4. Configure App

#### App Name

Edit `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:label="Enthrix"
    ... >
```

#### App Icon

Place your logo as `icon.png` in project root.

Generate icons:
```bash
flutter pub run flutter_launcher_icons
```

### 5. Build Configuration

#### Android

No additional configuration needed for debug builds.

For release builds, you'll need:
- Keystore file
- Key properties

Create `android/key.properties`:
```
storePassword=<password>
keyPassword=<password>
keyAlias=enthrix
storeFile=<path-to-keystore>
```

#### iOS

Open in Xcode:
```bash
cd ios
pod install
cd ..
```

Configure signing in Xcode:
1. Open `ios/Runner.xcworkspace`
2. Select Runner → Signing & Capabilities
3. Add your Apple ID
4. Select team

### 6. Run App

#### Debug Mode

```bash
# Connect device or start emulator
flutter devices

# Run app
flutter run
```

#### Release Mode (Android)

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Install:
```bash
flutter install
```

## Development Setup

### IDE Configuration

#### VS Code

Install extensions:
- Flutter
- Dart
- Flutter Tree
- Bracket Pair Colorizer

Add to `.vscode/launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Enthrix",
            "request": "launch",
            "type": "dart"
        }
    ]
}
```

#### Android Studio

1. Install Flutter plugin
2. Open project folder
3. Select device from dropdown
4. Click Run button

### Environment Variables

Create `.env` file in root (optional):
```
FIREBASE_API_KEY=your_api_key
FIREBASE_PROJECT_ID=your_project_id
```

Note: Not currently used by app, but good practice.

### Firebase Emulator (Optional)

For local development without Firebase:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize emulator
firebase init emulators

# Start emulator
firebase emulators:start
```

Configure app to use emulator in `main.dart`:
```dart
// Before Firebase.initializeApp()
FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
```

## Testing

### Unit Tests

```bash
flutter test
```

### Integration Tests

```bash
flutter test integration_test/app_test.dart
```

### Device Testing

Test on physical devices:
- Android 5.0+ (API 21)
- iOS 11.0+

## Troubleshooting

### Common Issues

#### Build Failures

**Problem:** Gradle sync fails
```bash
cd android
./gradlew clean
./gradlew build
cd ..
flutter clean
flutter pub get
```

**Problem:** CocoaPods error (iOS)
```bash
cd ios
pod deintegrate
pod install
cd ..
```

#### Firebase Issues

**Problem:** "Google Play Services" error
- Use physical device instead of emulator
- Or install Google Play on emulator

**Problem:** Authentication fails
- Check `google-services.json` is in correct location
- Verify package name matches
- Enable authentication methods in Firebase Console

#### Runtime Issues

**Problem:** Messages not sending
- Check Firestore rules allow writes
- Verify encryption keys initialized
- Check network connection

**Problem:** Encryption errors
- Clear app data
- Reinstall app (generates new keys)

### Debug Tips

1. **Enable Debug Logging**
   All services print debug info to console.

2. **Check Firestore Data**
   Use Firebase Console → Firestore to verify data.

3. **Test Encryption**
   Send message to yourself to test encryption loop.

4. **Verify Keys**
   Check user's public key in Firestore document.

## Production Deployment

### Pre-Deployment Checklist

- [ ] Test on multiple devices
- [ ] Verify encryption works
- [ ] Check offline functionality
- [ ] Review Firebase security rules
- [ ] Update app version
- [ ] Generate release build
- [ ] Test release build

### Android Release

1. Update version in `pubspec.yaml`:
```yaml
version: 1.0.0+1
```

2. Build APK:
```bash
flutter build apk --release
```

3. Or build App Bundle:
```bash
flutter build appbundle
```

4. Upload to Google Play Console

### iOS Release

1. Update version in Xcode

2. Build:
```bash
flutter build ios --release
```

3. Archive in Xcode

4. Upload to App Store Connect

## Security Configuration

### Firebase Security Rules

Update `firestore.rules`:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    match /messages/{userId}/incoming/{messageId} {
      allow read, write: if request.auth.uid == userId;
    }
    match /readReceipts/{userId}/receipts/{messageId} {
      allow read, write: if request.auth.uid == userId;
    }
  }
}
```

Deploy rules:
```bash
firebase deploy --only firestore:rules
```

## Next Steps

After setup:

1. Create test accounts
2. Send test messages
3. Verify encryption
4. Test offline mode
5. Review analytics

## Support

If you encounter issues:

1. Check Flutter doctor:
   ```bash
   flutter doctor -v
   ```

2. Review Firebase logs in Console

3. Check device logs:
   ```bash
   adb logcat
   ```

4. Open issue on GitHub
