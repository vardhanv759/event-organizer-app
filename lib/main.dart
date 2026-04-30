import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/payment_success_screen.dart';
import 'screens/payment_cancel_screen.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // ✅ SIMPLIFIED: No ThemeProvider wrapper
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Event Discovery App',
      debugShowCheckedModeBanner: false,
      routes: {
        '/payment-success': (context) => const PaymentSuccessScreen(),
        '/payment-cancel': (context) => const PaymentCancelScreen(),
      },

      // ✅ LIGHT THEME ONLY
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8FAFC),
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        cardColor: Colors.white,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF0F172A)),
          bodyMedium: TextStyle(color: Color(0xFF64748B)),
        ),
      ),

      // ❌ REMOVED: themeMode
      // ❌ REMOVED: darkTheme
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still connecting to Firebase
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          );
        }

        // No user -> show login/register screen
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Any logged-in user (verified or not) -> dashboard.
        // The dashboard itself will block features until email is verified.
        return const HomeScreen();
      },
    );
  }
}
