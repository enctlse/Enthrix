# API Documentation

## AuthService

Authentication and user management service.

### Methods

#### signInWithEmailAndPassword(String email, String password)
Authenticates user with email and password.

**Parameters:**
- `email` - User's email address
- `password` - User's password

**Returns:** `Future<UserModel?>` - User data if successful, null otherwise

**Throws:** FirebaseAuthException on authentication failure

---

#### signInWithGoogle()
Authenticates user using Google Sign-In.

**Returns:** `Future<UserModel?>` - User data if successful, null if cancelled

**Throws:** Exception on configuration errors

---

#### signOut()
Signs out current user and clears session data.

**Returns:** `Future<void>`

---

#### getUserData(String uid)
Retrieves user profile from Firestore.

**Parameters:**
- `uid` - User ID

**Returns:** `Future<UserModel?>` - User data or null if not found

---

#### updateUserProfile({String? name, String? username, String? bio})
Updates current user's profile information.

**Parameters:**
- `name` - Display name (optional)
- `username` - Unique username (optional)
- `bio` - User biography (optional)

**Returns:** `Future<void>`

---

#### deleteCurrentUser()
Permanently deletes current user account.

**Returns:** `Future<void>`

---

## MessageService

Messaging service for sending and receiving encrypted messages.

### Methods

#### initialize()
Initializes messaging service for current user.

**Returns:** `Future<void>`

**Note:** Must be called after user authentication

---

#### sendMessage(String receiverId, String text)
Sends encrypted message to another user.

**Parameters:**
- `receiverId` - Recipient's user ID
- `text` - Message content (plaintext)

**Returns:** `Future<bool>` - true if new chat created

**Throws:** Exception if encryption fails or network error

---

#### getMessages(String chatId)
Retrieves all messages for specific chat.

**Parameters:**
- `chatId` - Unique chat identifier

**Returns:** `List<MessageModel>` - List of messages

---

#### getUserChats(String userId)
Gets all active chats for user.

**Parameters:**
- `userId` - Current user's ID

**Returns:** `List<Map<String, dynamic>>` - Chat list with metadata

---

#### markMessagesAsRead(String chatId)
Marks all delivered messages in chat as read.

**Parameters:**
- `chatId` - Chat identifier

**Returns:** `Future<void>`

---

#### retryMessage(String chatId, String messageId)
Retries sending failed message.

**Parameters:**
- `chatId` - Chat identifier
- `messageId` - Message ID to retry

**Returns:** `Future<void>`

**Throws:** Exception if retry fails

---

## EncryptionService

End-to-end encryption service using RSA + AES.

### Methods

#### initialize(String userId)
Initializes encryption keys for user.

**Parameters:**
- `userId` - Current user's ID

**Returns:** `Future<void>`

**Behavior:**
- Loads existing keys from storage if available
- Generates new RSA key pair if not found
- Stores keys securely

---

#### getPublicKeyString()
Exports public key as string for sharing.

**Returns:** `String` - Base64 encoded public key

**Throws:** Exception if encryption not initialized

---

#### importPublicKey(String userId, String keyString)
Imports another user's public key.

**Parameters:**
- `userId` - User ID to associate with key
- `keyString` - Public key string

**Returns:** `void`

---

#### encryptMessage(String plainText, String receiverId)
Encrypts message for recipient.

**Parameters:**
- `plainText` - Message content
- `receiverId` - Recipient's user ID

**Returns:** `String` - Encrypted message data (base64)

**Encryption Process:**
1. Generates random AES key
2. Encrypts plaintext with AES
3. Encrypts AES key with recipient's RSA public key
4. Returns combined encrypted data

---

#### decryptMessage(String encryptedData)
Decrypts received message.

**Parameters:**
- `encryptedData` - Encrypted message (base64)

**Returns:** `String` - Decrypted plaintext

**Throws:** Exception if decryption fails

---

#### hasPublicKey(String userId)
Checks if public key exists for user.

**Parameters:**
- `userId` - User ID to check

**Returns:** `bool` - true if key exists

---

## Data Models

### UserModel

Represents user profile.

**Properties:**
- `uid` - Unique identifier
- `email` - Email address
- `name` - Display name
- `username` - Unique username
- `avatarUrl` - Profile picture URL
- `bio` - User biography
- `status` - Online status (online/offline)
- `lastSeen` - Last activity timestamp
- `createdAt` - Account creation timestamp

**Methods:**
- `fromMap(Map<String, dynamic>)` - Factory constructor from Firestore
- `toMap()` - Converts to Firestore format
- `copyWith(...)` - Creates modified copy

---

### MessageModel

Represents chat message.

**Properties:**
- `id` - Unique message ID
- `chatId` - Associated chat ID
- `senderId` - Sender's user ID
- `receiverId` - Recipient's user ID
- `text` - Decrypted message text
- `encryptedText` - Encrypted message data
- `timestamp` - Message timestamp
- `type` - Message type (text/image/file)
- `status` - MessageStatus enum
- `readAt` - Read timestamp

**MessageStatus Enum:**
- `sending` - Currently sending
- `sent` - On server
- `delivered` - Recipient received
- `read` - Recipient read
- `failed` - Send failed

**Methods:**
- `fromMap(Map<String, dynamic>)` - Factory from Firestore
- `fromLocalStorageMap(Map<String, dynamic>)` - Factory from local storage
- `toMap()` - Converts to Firestore format
- `toLocalStorageMap()` - Converts to local storage format
- `toServerMap()` - Converts to server format
- `copyWith(...)` - Creates modified copy

---

## Streams

### MessageService.messageStream
Stream of chat updates.

**Type:** `Stream<Map<String, List<MessageModel>>>`

**Emits:** Map where key is chatId and value is list of messages

**Usage:**
```dart
messageService.messageStream.listen((chats) {
  // Update UI with new chat data
});
```

---

### AuthService.authStateChanges
Stream of authentication state changes.

**Type:** `Stream<User?>`

**Emits:** Firebase User object or null if signed out

---

## Error Handling

All methods throw exceptions on errors:

### Authentication Errors
- `FirebaseAuthException` - Invalid credentials, network errors
- `Exception` - Configuration errors

### Messaging Errors
- `Exception` - Encryption/decryption failures
- `Exception` - Network errors
- `Exception` - Recipient public key not found

### Encryption Errors
- `Exception` - Keys not initialized
- `Exception` - Invalid key format
- `Exception` - Decryption failure (wrong private key)

---

## Security Notes

1. Never expose private keys
2. Always verify recipient's public key
3. Handle encryption errors gracefully
4. Clear sensitive data on sign out
5. Use secure storage for keys
