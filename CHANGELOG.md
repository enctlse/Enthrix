# Changelog

All notable changes to the Enthrix Messenger project.

## [1.0.0] - 2026-02-14

### Added

#### Core Features
- End-to-end encryption using RSA + AES
- Real-time messaging with Firebase Firestore
- User authentication (Email/Password and Google Sign-In)
- Local chat history storage
- Online/offline status
- Read receipts
- Dark and Light theme support

#### UI/UX
- Material Design 3 interface
- Custom chat bubbles with encryption indicator
- Bottom sheet for new chat creation
- Navigation drawer with user profile
- Settings screen
- Profile management

#### Security
- RSA 2048-bit key generation
- AES 256-bit message encryption
- Secure key storage (flutter_secure_storage)
- Ephemeral messages (auto-delete from server)
- Private key persistence across sessions

#### Technical
- Flutter 3.10.8+ support
- Firebase integration (Auth, Firestore, Storage)
- Cross-platform (Android, iOS, Web)
- Responsive design
- State management using streams

### Screens
- HomeScreen - Chat list with online status
- ChatScreen - Individual conversations
- LoginScreen - User authentication
- RegisterScreen - Account creation (multi-step)
- ProfileScreen - User profile management
- SettingsScreen - App preferences
- SearchScreen - Find users

### Services
- AuthService - Authentication and user management
- MessageService - Messaging and chat management
- EncryptionService - End-to-end encryption

### Models
- UserModel - User profile data
- MessageModel - Message data with encryption support

## Features in Development

### Planned for 1.1.0
- [ ] Group chat support
- [ ] Channel creation
- [ ] Contact list management
- [ ] Push notifications
- [ ] Message search
- [ ] Profile pictures

### Planned for 1.2.0
- [ ] Voice messages
- [ ] File sharing
- [ ] Message reactions
- [ ] Message forwarding
- [ ] Chat archiving

### Planned for 2.0.0
- [ ] Video calls
- [ ] Voice calls
- [ ] Screen sharing
- [ ] Desktop application
- [ ] Multi-device synchronization

## Technical Improvements

### Performance
- Optimized encryption operations
- Local message caching
- Efficient Firestore queries
- Image caching

### Security
- Biometric authentication
- App lock
- Screenshot protection
- Self-destructing messages

### Accessibility
- Screen reader support
- High contrast mode
- Font size adjustment
- Voice input

## Known Issues

### Current Limitations
1. Single device support only
2. No cloud backup
3. Device loss = message loss
4. No group chats
5. Limited file sharing

### Security Considerations
1. Keys stored locally
2. No forward secrecy
3. Metadata visible to server
4. No certificate pinning

## Deprecations

None in current release.

## Migration Guide

### From 0.x to 1.0
- Complete rewrite
- No migration path
- Fresh install required

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- MAJOR: Incompatible API changes
- MINOR: New functionality (backwards compatible)
- PATCH: Bug fixes (backwards compatible)

## Contributing

When contributing:
1. Update CHANGELOG.md
2. Follow semantic versioning
3. Tag releases
4. Write migration guides for breaking changes

---

For detailed API changes, see API.md
For architecture changes, see ARCHITECTURE.md
