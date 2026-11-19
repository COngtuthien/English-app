import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const BootstrapApp());
}

/// Shows the in-app splash screen while the offline database is prepared
/// (the first launch copies the bundled vocabulary database to app storage).
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});
  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  AppDatabase? _db;
  AppSettings? _settings;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final started = DateTime.now();
      await initializeDateFormatting('vi');
      final db = await AppDatabase.openForApp();
      final settings = await SettingsRepository(db.db).load();
      // keep the splash visible briefly so it does not flash
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 700)) {
        await Future.delayed(const Duration(milliseconds: 700) - elapsed);
      }
      setState(() {
        _db = db;
        _settings = settings;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_db != null && _settings != null) {
      return ProviderScope(
        overrides: [databaseProvider.overrideWithValue(_db!), initialSettingsProvider.overrideWithValue(_settings!)],
        child: const IeltsVocabularyApp(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SplashScreen(error: _error, onRetry: _start),
    );
  }
}

class SplashScreen extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  const SplashScreen({super.key, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/logo_small.png', width: 108, height: 108),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'IELTS Vocabulary Master',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Từ vựng IELTS 7.5+ • Học hoàn toàn ngoại tuyến',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 36),
                  if (error == null) ...[
                    const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                    const SizedBox(height: 14),
                    Text('Đang chuẩn bị dữ liệu từ vựng…', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                  ] else ...[
                    const Icon(Icons.error_outline, color: Colors.white, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Không thể mở cơ sở dữ liệu:\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: onRetry, child: const Text('Thử lại')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
