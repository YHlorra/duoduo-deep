import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dlg_q/core/providers/providers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('questionsPerLevelProvider 默认 5 且钳制到 5-20', () async {
    final container = ProviderContainer();
    // 等待 notifier 构造时的 _load（SharedPreferences）完成，避免 dispose 后异步写 state
    await Future.delayed(const Duration(milliseconds: 300));
    final notifier = container.read(questionsPerLevelProvider.notifier);

    expect(container.read(questionsPerLevelProvider), 5);

    notifier.set(25); // 上限钳制
    expect(container.read(questionsPerLevelProvider), 20);

    notifier.set(1); // 下限钳制
    expect(container.read(questionsPerLevelProvider), 5);

    notifier.set(15);
    expect(container.read(questionsPerLevelProvider), 15);

    notifier.set(20);
    expect(container.read(questionsPerLevelProvider), 20);

    // 等待 set 的异步持久化完成后再释放，避免 pending 回调触碰已 dispose 的 notifier
    await Future.delayed(const Duration(milliseconds: 50));
    container.dispose();
  });
}
