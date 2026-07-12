import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/providers.dart';

/// 每分钟触发一次体力恢复（apply）并刷新 UI（refresh）。
///
/// 接受回调而不是直接持有 `Ref`，让控制器既能在 Provider 也能在 WidgetRef
/// 上下文里复用。
class HeartRecoveryController {
  Timer? _timer;
  bool _ticking = false;
  final Future<void> Function() _apply;
  final void Function() _refresh;

  HeartRecoveryController({
    required Future<void> Function() apply,
    required void Function() refresh,
  })  : _apply = apply,
        _refresh = refresh;

  /// 启动/重启前台每分钟恢复 timer。反复调用安全。
  void startAutoRecovery() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  /// 仅取消前台 timer，保留 lastHeartRefill 持久化状态。
  void stopAutoRecovery() {
    _timer?.cancel();
    _timer = null;
  }

  /// 进入前台：先批量补离开期间的心，再启动分钟 timer。
  Future<void> onResume() async {
    await _tick();
    startAutoRecovery();
  }

  Future<void> _tick() async {
    // 防止 DB 写入未结束时下一次 tick 撞进来造成并发写。
    if (_ticking) return;
    _ticking = true;
    try {
      await _apply();
      _refresh();
    } finally {
      _ticking = false;
    }
  }
}

/// Riverpod 注入点：在 Provider scope 下组装 controller。
final heartRecoveryProvider = Provider<HeartRecoveryController>((ref) {
  Future<void> apply() =>
      ref.read(gamificationServiceProvider).applyHeartRecovery();
  void refresh() => ref.invalidate(userStatsProvider);
  final ctrl = HeartRecoveryController(apply: apply, refresh: refresh);
  ref.onDispose(ctrl.stopAutoRecovery);
  return ctrl;
});
