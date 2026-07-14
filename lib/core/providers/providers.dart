import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/app_prefs.dart';
import '../../data/models/deck.dart';
import '../../data/models/question.dart';
import '../../data/models/study_record.dart';
import '../../data/models/user_stats.dart';
import '../../services/content_analyzer.dart';
import '../../services/gamification_service.dart';
import '../../services/openai_service.dart';
import '../../services/socratic_dialog_service.dart';
import '../../services/sm2_algorithm.dart';

// ============ 概念掌握度 ============

/// 概念掌握度管理
final conceptMasteryProvider = StateNotifierProvider<ConceptMasteryNotifier, AsyncValue<List<ConceptMasteryInfo>>>((ref) {
  return ConceptMasteryNotifier(ref.read(databaseProvider));
});

class ConceptMasteryNotifier extends StateNotifier<AsyncValue<List<ConceptMasteryInfo>>> {
  final DatabaseHelper _db;

  ConceptMasteryNotifier(this._db) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final maps = await _db.getAllConceptMastery();
      final infos = maps.map((m) => ConceptMasteryInfo(
        name: m['concept_name'] as String,
        easeFactor: (m['ease_factor'] as num).toDouble(),
        intervalDays: m['interval_days'] as int,
        repetitions: m['repetitions'] as int,
        nextReviewDate: m['next_review_date'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['next_review_date'] as int)
            : null,
        lastResult: m['last_result'] as String?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      )).toList();
      state = AsyncValue.data(infos);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 更新概念掌握度（SM-2）
  Future<void> recordAnswer(String conceptName, {required bool correct, bool socraticUnderstood = false}) async {
    final existing = await _db.getConceptMastery(conceptName);
    final currentEase = existing?['ease_factor'] as double? ?? 2.5;
    final currentInterval = existing?['interval_days'] as int? ?? 0;
    final currentReps = existing?['repetitions'] as int? ?? 0;

    final quality = correct ? 4 : (socraticUnderstood ? 3 : 1);
    final result = sm2(
      easeFactor: currentEase,
      intervalDays: currentInterval,
      repetitions: currentReps,
      quality: quality,
    );

    await _db.updateConceptMastery(
      conceptName,
      easeFactor: result.easeFactor,
      intervalDays: result.intervalDays,
      repetitions: result.repetitions,
      nextReviewDate: result.nextReviewDate.millisecondsSinceEpoch,
      lastResult: correct ? 'correct' : 'wrong',
    );

    await _load();
  }

  /// 记录一道题的所有概念
  Future<void> recordQuestionAnswer(List<String> concepts, {required bool correct}) async {
    for (final concept in concepts) {
      if (concept.trim().isEmpty) continue;
      await recordAnswer(concept, correct: correct);
    }
  }

  /// 获取今日到期概念
  Future<List<String>> getDueConcepts() => _db.getDueConceptNames();

  /// 刷新
  Future<void> refresh() => _load();
}

// ============ 基础服务 Provider ============

final databaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

final openaiServiceProvider = Provider<OpenAIService>((ref) {
  return OpenAIService();
});

final contentAnalyzerProvider = Provider<ContentAnalyzer>((ref) {
  return ContentAnalyzer(ref.read(openaiServiceProvider));
});

final gamificationServiceProvider = Provider<GamificationService>((ref) {
  return GamificationService(ref.read(databaseProvider));
});

final socraticDialogServiceProvider = Provider<SocraticDialogService>((ref) {
  return SocraticDialogService(ref.read(openaiServiceProvider));
});

// ============ 数据 Provider ============

/// 所有题包列表
final deckListProvider = FutureProvider<List<Deck>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.getAllDecks();
});

/// 用户统计
final userStatsProvider = StateNotifierProvider<UserStatsNotifier, AsyncValue<UserStats>>((ref) {
  return UserStatsNotifier(ref.read(gamificationServiceProvider));
});

class UserStatsNotifier extends StateNotifier<AsyncValue<UserStats>> {
  final GamificationService _service;

  UserStatsNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await _service.getStats();
      state = AsyncValue.data(stats);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> onCorrect() async {
    final stats = await _service.onCorrectAnswer();
    state = AsyncValue.data(stats);
  }

  Future<void> onWrong() async {
    final stats = await _service.onWrongAnswer();
    state = AsyncValue.data(stats);
  }

  Future<void> onDeckComplete({required bool allCorrect}) async {
    final stats = await _service.onDeckComplete(allCorrect: allCorrect);
    state = AsyncValue.data(stats);
  }

  /// 完美完成答题，恢复一颗心
  Future<void> onPerfectQuiz() async {
    final stats = await _service.onPerfectQuiz();
    state = AsyncValue.data(stats);
  }

  Future<void> setDailyGoal(int goal) async {
    await _service.setDailyGoal(goal);
    await _load();
  }

  Future<void> refresh() async {
    await _load();
  }
}

/// 某题包的题目列表
final deckQuestionsProvider = FutureProvider.family<List<Question>, String>((ref, deckId) async {
  final db = ref.read(databaseProvider);
  return db.getQuestionsByDeck(deckId);
});

/// 某题包的学习记录
final studyRecordProvider = FutureProvider.family<StudyRecord?, String>((ref, deckId) async {
  final db = ref.read(databaseProvider);
  return db.getStudyRecord(deckId);
});

// ============ 操作 Provider ============

/// 题包操作
final deckOperationsProvider = Provider<DeckOperations>((ref) {
  return DeckOperations(ref);
});

class DeckOperations {
  final Ref _ref;
  DeckOperations(this._ref);

  /// 保存分析结果为题包
  Future<String> saveAnalysisResult(AnalysisResult result, {String? sourceText, String? sourceUrl, String? sourceImage}) async {
    final db = _ref.read(databaseProvider);
    final now = DateTime.now();
    final deckId = now.microsecondsSinceEpoch.toString();

    final deck = Deck(
      id: deckId,
      title: result.title,
      sourceText: sourceText,
      sourceUrl: sourceUrl,
      sourceImage: sourceImage,
      concepts: result.conceptNames,
      questionCount: result.questions.length,
      createdAt: now,
      updatedAt: now,
    );
    await db.insertDeck(deck);

    for (final question in result.questions) {
      await db.insertQuestion(Question(
        id: '',
        deckId: deckId,
        type: question.type,
        content: question.content,
        options: question.options,
        answer: question.answer,
        explanation: question.explanation,
        matchLeft: question.matchLeft,
        matchRight: question.matchRight,
        difficulty: question.difficulty,
        cognitiveLevel: question.cognitiveLevel,
      ));
    }

    // 刷新题包列表 + 随机模式题库
    _ref.invalidate(deckListProvider);
    _ref.invalidate(allQuestionsProvider);

    return deckId;
  }

  /// 删除题包
  Future<void> deleteDeck(String deckId) async {
    final db = _ref.read(databaseProvider);
    await db.deleteDeck(deckId);
    _ref.invalidate(deckListProvider);
  }

  /// 更新题包掌握度
  Future<void> updateMastery(String deckId, int masteryLevel) async {
    final db = _ref.read(databaseProvider);
    final deck = await db.getDeck(deckId);
    if (deck != null) {
      await db.updateDeck(deck.copyWith(masteryLevel: masteryLevel, updatedAt: DateTime.now()));
      _ref.invalidate(deckListProvider);
    }
  }

  /// 保存学习记录
  Future<void> saveStudyRecord(String deckId, int correctCount, int totalCount) async {
    final db = _ref.read(databaseProvider);
    final record = StudyRecord(
      id: '${deckId}_record',
      deckId: deckId,
      correctCount: correctCount,
      totalCount: totalCount,
      lastStudiedAt: DateTime.now(),
    );
    await db.upsertStudyRecord(record);

    // 更新掌握度
    final gamification = _ref.read(gamificationServiceProvider);
    final mastery = gamification.calculateMasteryLevel(correctCount, totalCount);
    await updateMastery(deckId, mastery);
  }
}

// ============ 学习模式 ============

/// 学习模式
enum LearningMode { random, knowledgePoint }

/// 学习模式 Provider（持久化到 SharedPreferences）
final learningModeProvider =
    StateNotifierProvider<LearningModeNotifier, LearningMode>((ref) {
  return LearningModeNotifier();
});

class LearningModeNotifier extends StateNotifier<LearningMode> {
  LearningModeNotifier() : super(LearningMode.random) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('learning_mode') ?? 0;
    state = LearningMode.values[index];
  }

  Future<void> setMode(LearningMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('learning_mode', mode.index);
  }
}

// ============ 苏格拉底式引导提问开关 ============

/// 苏格拉底式引导提问开关（默认关闭，opt-in，避免答错时强制消耗 token）
final socraticEnabledProvider =
    StateNotifierProvider<SocraticEnabledNotifier, bool>((ref) {
  return SocraticEnabledNotifier();
});

class SocraticEnabledNotifier extends StateNotifier<bool> {
  SocraticEnabledNotifier() : super(false) {
    _load();
  }

  static const _key = 'socratic_enabled';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // 默认关闭：用户需在设置中显式开启才消耗 token
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

// ============ 随机模式每关题量 ============

/// 随机模式每关抽题数量（默认 5，范围 5–20），持久化到 SharedPreferences。
/// 用户在设置页调整，home_screen 随机关卡据此数量抽题。
final questionsPerLevelProvider =
    StateNotifierProvider<QuestionsPerLevelNotifier, int>((ref) {
  return QuestionsPerLevelNotifier();
});

class QuestionsPerLevelNotifier extends StateNotifier<int> {
  QuestionsPerLevelNotifier() : super(5) {
    _load();
  }

  static const _key = 'questions_per_level';
  static const min = 5;
  static const max = 20;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key) ?? 5;
    state = v.clamp(min, max);
  }

  Future<void> set(int v) async {
    state = v.clamp(min, max);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, state);
  }
}

// ============ 学习偏好设置 ============

/// 学习偏好设置
final appPrefsProvider =
    StateNotifierProvider<AppPrefsNotifier, AsyncValue<AppPrefs>>((ref) {
  return AppPrefsNotifier();
});

class AppPrefsNotifier extends StateNotifier<AsyncValue<AppPrefs>> {
  AppPrefsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await AppPrefs.load();
      state = AsyncValue.data(prefs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(AppPrefs prefs) async {
    await prefs.save();
    state = AsyncValue.data(prefs);
  }
}

// ============ 随机关卡进度 ============

/// 随机模式已通关数（持久化）
final randomLevelProgressProvider =
    StateNotifierProvider<RandomLevelNotifier, int>((ref) {
  return RandomLevelNotifier();
});

class RandomLevelNotifier extends StateNotifier<int> {
  RandomLevelNotifier() : super(0) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('random_level_progress') ?? 0;
  }

  /// 标记某关为已完成（只增不减）
  Future<void> completeLevel(int level) async {
    if (level > state) {
      state = level;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('random_level_progress', level);
    }
  }
}

// ============ 所有题目（随机模式用） ============

final allQuestionsProvider = FutureProvider<List<Question>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.getAllQuestions();
});

// ============ 月度打卡 & 答题统计 ============

/// 当月打卡日期列表（key 格式: "2026_6"）
final monthlyCheckInProvider = FutureProvider.family<List<String>, String>((ref, yearMonth) async {
  final parts = yearMonth.split('_');
  return ref.read(gamificationServiceProvider)
      .getMonthlyCheckInDates(int.parse(parts[0]), int.parse(parts[1]));
});

/// 已获得的月度勋章
final earnedMedalsProvider = FutureProvider<List<({int year, int month})>>((ref) async {
  return ref.read(gamificationServiceProvider).getEarnedMedals();
});

/// 总答对题数
final totalCorrectProvider = FutureProvider<int>((ref) async {
  return ref.read(gamificationServiceProvider).getTotalCorrect();
});

/// 完美通关次数
final perfectCountProvider = FutureProvider<int>((ref) async {
  return ref.read(gamificationServiceProvider).getPerfectCount();
});
