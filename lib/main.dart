import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'features/auth/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint('================================');
    debugPrint('FIREBASE INITIALIZATION ERROR');
    debugPrint('$e');
    debugPrint('$stackTrace');
    debugPrint('================================');

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'خطأ في تهيئة Firebase:\n\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // =====================================================
      // معلومات التطبيق
      // =====================================================

      title: 'نظام إدارة المشاريع',

      // =====================================================
      // اللغة العربية
      // =====================================================

      locale: const Locale('ar'),

      // =====================================================
      // الاتجاه العربي
      // =====================================================

      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },

      // =====================================================
      // Theme
      // =====================================================

      theme: ThemeData(
        useMaterial3: true,

        // الاتجاه الافتراضي للنصوص
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          titleSmall: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),

        // ===================================================
        // AppBar
        // ===================================================

        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),

        // ===================================================
        // Input
        // ===================================================

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(12),
            ),
            borderSide: BorderSide(
              width: 2,
            ),
          ),
        ),

        // ===================================================
        // Elevated Button
        // ===================================================

        elevatedButtonTheme:
            ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(
              double.infinity,
              50,
            ),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12),
            ),
          ),
        ),

        // ===================================================
        // Card
        // ===================================================

        cardTheme: CardThemeData(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(14),
          ),
        ),
      ),

      // =====================================================
      // الصفحة الأولى
      // =====================================================

      home: const LoginPage(),
    );
  }
}