# Architecture Documentation

## Overview

Enthrix uses a client-side encryption architecture with Firebase as the transport layer. Messages are end-to-end encrypted and ephemeral.

## System Architecture

```
┌─────────────────┐
│   Client App    │
│  (Flutter)      │
├─────────────────┤
│  UI Layer       │
│  Business Logic │
│  Encryption     │
│  Local Storage  │
└────────┬────────┘
         │ HTTPS/WSS
         ▼
┌─────────────────┐
│   Firebase      │
│                 │
│  Authentication │
│  Firestore      │
│  Cloud Storage  │
└─────────────────┘
```

## Encryption Architecture

### Hybrid Encryption

Uses RSA + AES hybrid encryption:

1. **RSA 2048-bit** - For key exchange
   - Each user has unique key pair
   - Public key shared via Firestore
   - Private key kept secure locally

2. **AES 256-bit** - For message content
   - Random key generated per message
   - Key encrypted with RSA
   - Message encrypted with AES

### Encryption Flow

```
Sender:
  ┌─────────────┐
  │  Plaintext  │
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │  AES Key    │ (Random 256-bit)
  └──────┬──────┘
         │
         ├──► Encrypt Plaintext
         │
         ▼
  ┌─────────────┐
  │ RSA Public  │
  │    Key      │
  └──────┬──────┘
         │
         ├──► Encrypt AES Key
         │
         ▼
  ┌─────────────┐
  │ Encrypted   │
  │  Message    │ (AES ciphertext + RSA encrypted key)
  └──────┬──────┘
         │
         ▼
      Firestore

Recipient:
  ┌─────────────┐
  │ Encrypted   │
  │  Message    │
  └──────┬──────┘
         │
         ├──► RSA Private Key
         │         │
         │         ▼
         │    Decrypt AES Key
         │         │
         ▼         ▼
    Decrypt Message
         │
         ▼
  ┌─────────────┐
  │  Plaintext  │
  └─────────────┘
```

## Data Flow

### User Registration

1. User creates account (email/password or Google)
2. Firebase Auth creates user
3. Firestore stores user profile
4. EncryptionService generates RSA key pair
5. Public key saved to Firestore
6. Private key saved to secure storage

### Sending Message

1. User selects recipient
2. App fetches recipient's public key
3. Message encrypted (AES + RSA)
4. Encrypted data sent to Firestore
5. Local copy saved with "sending" status
6. Firestore listener confirms delivery
7. Status updated to "sent"

### Receiving Message

1. Firestore listener detects new message
2. App decrypts AES key with private key
3. App decrypts message content
4. Message saved locally with "delivered" status
5. Read receipt sent to sender
6. Message marked for server deletion

### User Goes Online

1. App initializes
2. Auth state confirmed
3. Encryption keys loaded
4. Pending messages fetched
5. Real-time listener started
6. Status set to "online"

## Security Model

### Threats Addressed

✅ **Man-in-the-Middle**
- RSA encryption ensures only recipient can read
- Keys exchanged via authenticated channel (Firebase)

✅ **Server Compromise**
- Server only sees encrypted data
- No plaintext stored
- Keys never transmitted

✅ **Message Interception**
- End-to-end encryption
- Ephemeral messages (deleted after delivery)

### Security Limitations

⚠️ **Device Compromise**
- Private keys stored on device
- Physical access = key access

⚠️ **Screen Capture**
- No protection against screenshots
- Message content visible in UI

⚠️ **Metadata**
- Server sees who talks to whom
- Timestamps and message sizes visible

## Storage Architecture

### Local Storage

**SharedPreferences:**
```
chats_<userId>     → JSON encoded chat history
<userId>_public_*  → RSA public key components
<userId>_private_* → RSA private key components
```

**In-Memory:**
```
_localMessages     → Map<chatId, List<MessageModel>>
_publicKeys        → Map<userId, RSAPublicKey>
_encryptionKeys    → AsymmetricKeyPair
```

### Firebase Storage

**Firestore Collections:**

```
users/{uid}
  - uid: string
  - email: string
  - name: string
  - username: string
  - publicKey: string
  - status: string
  - lastSeen: timestamp
  - createdAt: timestamp

messages/{userId}/incoming/{messageId}
  - id: string
  - chatId: string
  - senderId: string
  - receiverId: string
  - encryptedText: string
  - timestamp: timestamp
  - delivered: boolean
  - expiresAt: timestamp

readReceipts/{userId}/receipts/{messageId}
  - messageId: string
  - readAt: timestamp
```

## Component Architecture

### Service Layer

```
┌─────────────────────────────────────┐
│           AuthService               │
│  ┌─────────┐  ┌─────────────────┐  │
│  │  Auth   │  │   User Profile  │  │
│  │  State  │  │   Management    │  │
│  └─────────┘  └─────────────────┘  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│         MessageService              │
│  ┌─────────┐  ┌─────────┐  ┌─────┐ │
│  │ Message │  │   Chat  │  │Read │ │
│  │ Sending │  │Management│ │Receipt││
│  └─────────┘  └─────────┘  └─────┘ │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│       EncryptionService             │
│  ┌─────────┐  ┌─────────────────┐  │
│  │  Key    │  │  Encrypt/Decrypt │  │
│  │Management│  │   Operations    │  │
│  └─────────┘  └─────────────────┘  │
└─────────────────────────────────────┘
```

### UI Layer

```
HomeScreen (Chat List)
    │
    ├── ChatScreen (Individual Chat)
    │
    ├── ProfileScreen (User Profile)
    │
    ├── SettingsScreen (App Settings)
    │
    └── SearchScreen (Find Users)
```

## State Management

### Authentication State
- Managed by Firebase Auth
- Stream: `authStateChanges`
- Singleton pattern via `AuthService`

### Message State
- Local storage + Stream
- Stream: `messageStream`
- Updates pushed to all listeners

### UI State
- StatefulWidget for screen state
- InheritedWidget for theme
- No external state management library

## Performance Considerations

### Optimizations

1. **Lazy Loading**
   - Messages loaded on demand
   - Images cached locally

2. **Encryption Caching**
   - Public keys cached in memory
   - Avoid repeated Firestore calls

3. **Pagination**
   - Chat list not paginated (all local)
   - Messages loaded from local storage

4. **Background Sync**
   - Polling every 5 seconds as backup
   - Real-time listeners for immediate updates

### Bottlenecks

1. **Encryption/Decryption**
   - RSA operations are CPU intensive
   - Performed on main thread (could be improved)

2. **Firestore Reads**
   - User profiles fetched frequently
   - Could implement local caching

3. **Image Loading**
   - No image optimization implemented
   - Full resolution images loaded

## Scalability

### Current Limits

- **Users**: Limited by Firebase free tier
- **Messages**: No server storage (ephemeral)
- **Chats**: Limited by device storage
- **Groups**: Not implemented

### Scaling Considerations

1. **Sharding**
   - Messages collection sharded by userId
   - Each user has own subcollection

2. **Rate Limiting**
   - Firestore has built-in limits
   - No client-side rate limiting

3. **Offline Support**
   - Firestore offline persistence enabled
   - Messages queued when offline
   - Auto-sync when connection restored

## Deployment Architecture

### Build Pipeline

```
Development
    │
    ├── Local Testing (Emulator)
    │
    ├── Firebase Test Lab
    │
    └── Production Build
            │
            ├── Android (APK/AAB)
            │
            └── iOS (IPA)
```

### Release Checklist

1. Update version in `pubspec.yaml`
2. Run tests: `flutter test`
3. Build release: `flutter build apk --release`
4. Test on physical device
5. Upload to Play Store / App Store

## Future Architecture

### Planned Improvements

1. **Multi-Device Support**
   - Key synchronization
   - Cloud backup option

2. **Group Chats**
   - Sender keys
   - Group management

3. **Media Messages**
   - Encryption for files
   - Thumbnail generation

4. **Push Notifications**
   - FCM integration
   - Notification encryption

5. **Desktop App**
   - Flutter Desktop support
   - Shared code base

## Monitoring

### Logging

- All services use print() for logging
- Production should use proper logging framework
- Consider Firebase Crashlytics

### Metrics

Not currently implemented:
- Message delivery rate
- Encryption performance
- User engagement
- Error rates

## Conclusion

This architecture provides:
- ✅ End-to-end encryption
- ✅ Real-time messaging
- ✅ Offline support
- ✅ Cross-platform support
- ⚠️ Single device limitation
- ⚠️ No cloud backup
