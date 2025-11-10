// File generated based on provided JSON data.
// Generated using available data for Android ONLY.
// It's strongly recommended to use the FlutterFire CLI ('flutterfire configure')
// to ensure accuracy and completeness across all platforms.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
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
      // Throw an error or return placeholder options if web support is needed
      // but not configured here.
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
            'configuration data was not provided.',
      );
      // return web; // Uncomment this if you configure 'web' below
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      // Throw an error or return placeholder options if iOS support is needed
      // but not configured here.
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
              'configuration data was not provided.',
        );
    // return ios; // Uncomment this if you configure 'ios' below
      case TargetPlatform.macOS:
      // Throw an error or return placeholder options if macOS support is needed
      // but not configured here.
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
              'configuration data was not provided.',
        );
    // return macos; // Uncomment this if you configure 'macos' below
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
              'configuration data was not provided.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
              'configuration data was not provided.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ------------------ ANDROID OPTIONS ------------------
  // Values extracted or derived from the provided JSON data.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBpDPQNK2tTZyVRlJTbnUJl-L4gCKfI41w', // from client[0].api_key[0].current_key
    appId: '1:87093297850:android:72be072191e405c677b883', // from client[0].client_info.mobilesdk_app_id
    messagingSenderId: '87093297850', // Assumed from project_info.project_number
    projectId: 'presencepointmuj', // from project_info.project_id
    databaseURL: 'https://presencepointmuj-default-rtdb.asia-southeast1.firebasedatabase.app', // from project_info.firebase_url
    storageBucket: 'presencepointmuj.firebasestorage.app', // from project_info.storage_bucket
    // authDomain: 'presencepointmuj.firebaseapp.com', // Derived from project_id (Optional, uncomment if needed)
    // measurementId: 'G-XXXXXXXXXX', // Not provided in the JSON (Optional, add if using Analytics)
  );


// ------------------ PLACEHOLDER OPTIONS ------------------
// These need to be filled with actual configuration data if you support these platforms.

/*
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'presencepointmuj',
    authDomain: 'presencepointmuj.firebaseapp.com', // Usually derived
    databaseURL: 'https://presencepointmuj-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'presencepointmuj.firebasestorage.app',
    measurementId: 'YOUR_WEB_MEASUREMENT_ID', // Optional
  );
  */

/*
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY', // Usually same as Android/Web
    appId: 'YOUR_IOS_APP_ID', // e.g., 1:87093297850:ios:xxxxxxxxxxxxxx
    messagingSenderId: '87093297850',
    projectId: 'presencepointmuj',
    databaseURL: 'https://presencepointmuj-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'presencepointmuj.firebasestorage.app',
    iosBundleId: 'com.adikr.presencepoint', // Your iOS Bundle ID
    // iosClientId: 'YOUR_IOS_CLIENT_ID', // Optional, for Google Sign-In
    // gcmSenderID: '87093297850', // Often same as messagingSenderId
  );
  */

/*
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY', // Usually same as Android/Web
    appId: 'YOUR_MACOS_APP_ID', // e.g., 1:87093297850:ios:xxxxxxxxxxxxxx (often uses iOS ID structure)
    messagingSenderId: '87093297850',
    projectId: 'presencepointmuj',
    databaseURL: 'https://presencepointmuj-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'presencepointmuj.firebasestorage.app',
    iosBundleId: 'com.adikr.presencepoint.Runner', // Your macOS Bundle ID (check Xcode)
     // iosClientId: 'YOUR_MACOS_CLIENT_ID', // Optional, for Google Sign-In
     // gcmSenderID: '87093297850', // Often same as messagingSenderId
  );
  */

}