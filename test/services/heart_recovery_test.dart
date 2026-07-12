// Regression tests for the heart auto-recovery feature (1 heart per minute).
//
// Targets the pure function `GamificationService.computeHeartRecovery` so
// the math is exercised without standing up SQLite. The DB write path lives
// in `applyHeartRecovery` (instantiated in app) and is trivially covered by
// the existing full-suite run.

import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/data/models/user_stats.dart';
import 'package:dlg_q/services/gamification_service.dart';

UserStats _stats({
  int hearts = 4,
  int maxHearts = 5,
  DateTime? lastHeartRefill,
}) {
  return UserStats(
    hearts: hearts,
    maxHearts: maxHearts,
    lastStudyDate: DateTime(2024, 1, 1),
    lastHeartRefill: lastHeartRefill ?? DateTime(2024, 1, 1, 12, 0, 0),
  );
}

void main() {
  group('computeHeartRecovery (1 heart per minute)', () {
    test('zero elapsed minutes — no refill, identical object returned', () {
      final now = DateTime(2024, 1, 1, 12, 0, 30); // 30 sec later
      final stats = _stats(hearts: 4, lastHeartRefill: DateTime(2024, 1, 1, 12, 0, 0));
      final out = GamificationService.computeHeartRecovery(stats, clock: () => now);
      expect(identical(out, stats), isTrue,
          reason: 'zero elapsed must return same object to skip DB write');
      expect(out.hearts, 4);
    });

    test('exactly 60s elapsed — recovers +1, advances lastHeartRefill', () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      final now = base.add(const Duration(seconds: 60));
      final out = GamificationService.computeHeartRecovery(
        _stats(hearts: 4, lastHeartRefill: base),
        clock: () => now,
      );
      expect(out.hearts, 5);
      expect(out.lastHeartRefill, base.add(const Duration(minutes: 1)));
    });

    test('2 minutes elapsed — recovers +2', () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      final out = GamificationService.computeHeartRecovery(
        _stats(hearts: 3, lastHeartRefill: base),
        clock: () => base.add(const Duration(minutes: 2)),
      );
      expect(out.hearts, 5);
      expect(out.lastHeartRefill, base.add(const Duration(minutes: 2)));
    });

    test('elapsed exceeds gap to max — caps at maxHearts, no overfill', () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      final out = GamificationService.computeHeartRecovery(
        _stats(hearts: 2, maxHearts: 5, lastHeartRefill: base),
        clock: () => base.add(const Duration(minutes: 30)),
      );
      expect(out.hearts, 5);
      // lastHeartRefill advances by elapsedMinutes (30), not by max-fill amount.
      // Caller can call again; next iteration will see "0 elapsed to spare" and
      // return identical. This is idempotent.
      expect(out.lastHeartRefill, base.add(const Duration(minutes: 30)));
    });

    test('already at max — identical object returned, no work', () {
      final stats = _stats(hearts: 5);
      final out = GamificationService.computeHeartRecovery(
        stats,
        clock: () => DateTime(2024, 1, 1, 13, 0, 0),
      );
      expect(identical(out, stats), isTrue);
    });

    test('clock skew (future lastHeartRefill) — no negative recovery', () {
      final future = DateTime(2024, 1, 1, 13, 0, 0);
      final stats = _stats(hearts: 4, lastHeartRefill: future);
      final out = GamificationService.computeHeartRecovery(
        stats,
        clock: () => DateTime(2024, 1, 1, 12, 0, 0), // earlier than lastRefill
      );
      expect(out.hearts, 4);
      expect(out.lastHeartRefill, future);
    });

    test('partial minute (59s) does not recover — sub-minute precision', () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      final stats = _stats(hearts: 4, lastHeartRefill: base);
      final out = GamificationService.computeHeartRecovery(
        stats,
        clock: () => base.add(const Duration(seconds: 59)),
      );
      expect(out.hearts, 4);
      expect(out.lastHeartRefill, base);
    });

    test('idempotency: calling twice in a row with no extra elapsed second',
        () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      final initial = _stats(hearts: 3, lastHeartRefill: base);
      final now = base.add(const Duration(minutes: 5));
      final first = GamificationService.computeHeartRecovery(
        initial,
        clock: () => now,
      );
      final second = GamificationService.computeHeartRecovery(
        first,
        clock: () => now,
      );
      expect(second.hearts, 5);
      expect(second.lastHeartRefill, first.lastHeartRefill);
    });
  });
}