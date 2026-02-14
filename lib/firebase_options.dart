import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA0V03pX5eCBvytm7dCv5bx-Uo5e3ChcIA',
    appId: '1:277454719789:web:0345fdac4996092087e1a4',
    messagingSenderId: '277454719789',
    projectId: 'enthrix-b5bc9',
    authDomain: 'enthrix-b5bc9.firebaseapp.com',
    storageBucket: 'enthrix-b5bc9.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0V03pX5eCBvytm7dCv5bx-Uo5e3ChcIA',
    appId: '1:277454719789:android:0345fdac4996092087e1a4',
    messagingSenderId: '277454719789',
    projectId: 'enthrix-b5bc9',
    storageBucket: 'enthrix-b5bc9.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA0V03pX5eCBvytm7dCv5bx-Uo5e3ChcIA',
    appId: '1:277454719789:ios:0345fdac4996092087e1a4',
    messagingSenderId: '277454719789',
    projectId: 'enthrix-b5bc9',
    storageBucket: 'enthrix-b5bc9.firebasestorage.app',
    iosBundleId: 'com.example.enthrixMessenger',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA0V03pX5eCBvytm7dCv5bx-Uo5e3ChcIA',
    appId: '1:277454719789:ios:0345fdac4996092087e1a4',
    messagingSenderId: '277454719789',
    projectId: 'enthrix-b5bc9',
    storageBucket: 'enthrix-b5bc9.firebasestorage.app',
    iosBundleId: 'com.example.enthrixMessenger',
  );
}
