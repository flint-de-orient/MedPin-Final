import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/registry.dart';
import 'app/splash.dart';
import 'core/nav.dart';
import 'core/tokens.dart';
import 'data/firebase_phone.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Nav.registry = screenRegistry;
  FirebasePhone.I.init(); // SMS sign-in on Android; ready long before the Login screen
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: MP.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const MedPinApp());
}

class MedPinApp extends StatelessWidget {
  const MedPinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedPin',
      debugShowCheckedModeBanner: false,
      theme: medpinTheme(),
      navigatorKey: Nav.key,
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        final s = Nav.spec(settings.name ?? '');
        if (s == null) return null;
        return MaterialPageRoute(settings: settings, builder: s.builder);
      },
    );
  }
}
