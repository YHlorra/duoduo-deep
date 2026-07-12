import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../features/home/home_screen.dart';
import '../features/deck/deck_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/ingestion/ingestion_screen.dart';
import '../services/heart_recovery.dart';

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription? _sharingSubscription;

  final _screens = const [
    HomeScreen(),
    DeckListScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进 app 直接给前台分钟 timer；首批心数在 onResume 里也跑一次 apply。
    ref.read(heartRecoveryProvider).startAutoRecovery();
    if (!kIsWeb) {
      _initSharingIntent();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = ref.read(heartRecoveryProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        ctrl.onResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        ctrl.stopAutoRecovery();
    }
  }

  void _initSharingIntent() {
    try {
      // 处理 APP 通过分享启动时的内容(文本和图片)
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(files);
        }
        ReceiveSharingIntent.instance.reset();
      }).catchError((_) {});

      // 监听 APP 运行时的分享事件
      _sharingSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(files);
        }
      });
    } catch (e) {
      // release 模式下初始化失败时静默处理，不影响正常渲染
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    String? text;
    String? imagePath;

    for (final file in files) {
      if (file.type == SharedMediaType.text) {
        text = file.path; // 文本内容在 path 字段
      } else if (file.type == SharedMediaType.image) {
        imagePath = file.path;
      }
    }

    if (text != null || imagePath != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IngestionScreen(
            sharedText: text,
            sharedImagePath: imagePath,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _sharingSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ref.read(heartRecoveryProvider).stopAutoRecovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '学习',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.quiz_outlined),
            activeIcon: Icon(Icons.quiz),
            label: '题库',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
