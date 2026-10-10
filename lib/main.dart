import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_lock.dart';
import 'app/registry.dart';
import 'app/splash.dart';
import 'core/nav.dart';
import 'core/tokens.dart';
import 'data/api.dart';
import 'data/firebase_phone.dart';
import 'data/med_alarms.dart';
import 'data/push.dart';
import 'data/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Nav.registry = screenRegistry;
  FirebasePhone.I
      .init(); // SMS sign-in on Android; ready long before the Login screen
  // Push notifications start once someone is signed in (restored or new).
  Session.I.deviceToken = () => Push.I.token;
  Api.I.onMedicinesChanged = MedAlarms.I.sync;
  var wasSignedIn = false;
  Session.I.addListener(() {
    final now = Session.I.signedIn;
    if (now && !wasSignedIn) {
      Push.I.start();
      MedAlarms.I.start(); // patients only; staff have no medicine alarms
    }
    if (!now && wasSignedIn) {
      Push.I.forget();
      MedAlarms.I.clear();
    }
    wasSignedIn = now;
  });
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: MP.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MedPinApp());
}

class MedPinApp extends StatelessWidget {
  const MedPinApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The account language (English, বাংলা, हिन्दी) sets the app locale; every Text follows it.
    return ListenableBuilder(
      listenable: Session.I,
      builder:
          (context, _) => MaterialApp(
            title: 'MedPin',
            debugShowCheckedModeBanner: false,
            locale: Locale(switch (Session.I.user['language']) {
              'bn' => 'bn',
              'hi' => 'hi',
              _ => 'en',
            }),
            supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: medpinTheme(),
            navigatorKey: Nav.key,
            // App lock covers every screen when it's on (see AppLockGate).
            builder:
                (context, child) =>
                    AppLockGate(child: child ?? const SizedBox.shrink()),
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              final s = Nav.spec(settings.name ?? '');
              if (s == null) return null;
              return MaterialPageRoute(settings: settings, builder: s.builder);
            },
          ),
    );
  }
}
