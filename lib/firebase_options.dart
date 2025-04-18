// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
    

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
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
        return windows;
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
    apiKey: 'AIzaSyD2NDyEe7SH3g2mUEu6XWpLrP4NxJptAiA',
    appId: '1:157804352950:web:9439e025c4bc0bfb031d17',
    messagingSenderId: '157804352950',
    projectId: 'bodaboda-b5aa8',
    authDomain: 'bodaboda-b5aa8.firebaseapp.com',
    storageBucket: 'bodaboda-b5aa8.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDMvL9o7v_Je-RP-LutapvT0FDwxVQU-nw',
    appId: '1:157804352950:android:8491a095d6edbe70031d17', //1:157804352950:android:92ad98523fccbc70031d17
    messagingSenderId: '157804352950',
    projectId: 'bodaboda-b5aa8',
    storageBucket: 'bodaboda-b5aa8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDAkdhRB9BsOIV693PZ4nPOXfklh9A4nAM',
    appId: '1:157804352950:ios:ef2791f6864e33c2031d17',
    messagingSenderId: '157804352950',
    projectId: 'bodaboda-b5aa8',
    storageBucket: 'bodaboda-b5aa8.firebasestorage.app',
    iosBundleId: 'com.example.bodaBodaApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDAkdhRB9BsOIV693PZ4nPOXfklh9A4nAM',
    appId: '1:157804352950:ios:ef2791f6864e33c2031d17',
    messagingSenderId: '157804352950',
    projectId: 'bodaboda-b5aa8',
    storageBucket: 'bodaboda-b5aa8.firebasestorage.app',
    iosBundleId: 'com.example.bodaBodaApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD2NDyEe7SH3g2mUEu6XWpLrP4NxJptAiA',
    appId: '1:157804352950:web:d117e401afed8b27031d17',
    messagingSenderId: '157804352950',
    projectId: 'bodaboda-b5aa8',
    authDomain: 'bodaboda-b5aa8.firebaseapp.com',
    storageBucket: 'bodaboda-b5aa8.firebasestorage.app',
  );
}
