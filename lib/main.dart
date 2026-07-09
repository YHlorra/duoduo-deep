import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/theme/app_theme.dart';
import 'services/log_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize log service (500-entry ring buffer)
    LogService.instance.setCapacity(500);

    // 捕获 Flutter 框架渲染错误
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.instance.log('app', 'error', 'flutter_error', {
        'exception': details.exceptionAsString(),
      });
    };

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    runApp(
      const ProviderScope(
        child: DIYDuolingoApp(),
      ),
    );
  }, (error, stack) {
    // 捕获所有未处理的异步异常
    LogService.instance.log('app', 'error', 'zone_error', {
      'error': error.toString(),
      'stack': stack.toString(),
    });
  });
}

class DIYDuolingoApp extends StatelessWidget {
  const DIYDuolingoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // widget 构建失败时显示错误信息，而不是灰色界面
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '渲染错误:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    return MaterialApp(
      title: '多多学',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainApp(),
    );
  }
}
