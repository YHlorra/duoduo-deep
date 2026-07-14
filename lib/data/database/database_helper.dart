import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/deck.dart';
import '../models/question.dart';
import '../models/study_record.dart';
import '../models/user_stats.dart';

/// SQLite 数据库帮助类
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      return _WebDatabase();
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'dlg_q.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 题包表
    await db.execute('''
      CREATE TABLE decks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source_text TEXT,
        source_url TEXT,
        source_image TEXT,
        concepts TEXT,
        question_count INTEGER DEFAULT 0,
        mastery_level INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 题目表
    await db.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        options TEXT,
        answer TEXT NOT NULL,
        explanation TEXT,
        match_left TEXT,
        match_right TEXT,
        difficulty TEXT,
        cognitive_level TEXT,
        last_shown_at INTEGER,
        last_result TEXT,
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_questions_last_shown ON questions(last_shown_at)',
    );

    // 学习记录表
    await db.execute('''
      CREATE TABLE study_records (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        correct_count INTEGER DEFAULT 0,
        total_count INTEGER DEFAULT 0,
        last_studied_at INTEGER NOT NULL,
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE
      )
    ''');

    // 用户统计表(单行)
    await db.execute('''
      CREATE TABLE user_stats (
        id INTEGER PRIMARY KEY DEFAULT 1,
        xp INTEGER DEFAULT 0,
        streak INTEGER DEFAULT 0,
        hearts INTEGER DEFAULT 5,
        max_hearts INTEGER DEFAULT 5,
        last_study_date INTEGER NOT NULL,
        daily_goal INTEGER DEFAULT 50,
        today_xp INTEGER DEFAULT 0,
        last_heart_refill INTEGER NOT NULL
      )
    ''');

    // 概念掌握度表
    await db.execute('''
      CREATE TABLE concept_mastery (
        concept_name TEXT PRIMARY KEY,
        ease_factor REAL DEFAULT 2.5,
        interval_days INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        next_review_date INTEGER,
        last_result TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 概念定义表（跨题包共享，深度模式 Phase 1.5 写入）
    await db.execute('''
      CREATE TABLE concepts (
        concept_name TEXT PRIMARY KEY,
        description TEXT,
        key_points TEXT,
        source_deck_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 初始化用户统计
    await db.insert('user_stats', {
      'id': 1,
      'xp': 0,
      'streak': 0,
      'hearts': 5,
      'max_hearts': 5,
      'last_study_date': DateTime.now().millisecondsSinceEpoch,
      'daily_goal': 50,
      'today_xp': 0,
      'last_heart_refill': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE questions ADD COLUMN difficulty TEXT');
      await db.execute('ALTER TABLE questions ADD COLUMN cognitive_level TEXT');
      await db.execute('ALTER TABLE decks ADD COLUMN source_url TEXT');
      await db.execute('ALTER TABLE decks ADD COLUMN concepts TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS concept_mastery (
          concept_name TEXT PRIMARY KEY,
          ease_factor REAL DEFAULT 2.5,
          interval_days INTEGER DEFAULT 0,
          repetitions INTEGER DEFAULT 0,
          next_review_date INTEGER,
          last_result TEXT,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // Heuristic: 1-per-minute heart refill. Column is NOT NULL, so existing
      // rows must be filled explicitly — don't rely on fromMap defaults.
      await db.execute('ALTER TABLE user_stats ADD COLUMN last_heart_refill INTEGER');
      await db.rawUpdate(
        'UPDATE user_stats SET last_heart_refill = ? WHERE last_heart_refill IS NULL',
        [DateTime.now().millisecondsSinceEpoch],
      );
    }
    if (oldVersion < 4) {
      // ponytail: 题目级冷却 — 概念层 SM-2 已存 concept_mastery 表，
      // 题目层只加 last_shown_at/last_result 两列做短期去重，不重复造 SM-2。
      await db.execute('ALTER TABLE questions ADD COLUMN last_shown_at INTEGER');
      await db.execute('ALTER TABLE questions ADD COLUMN last_result TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_questions_last_shown ON questions(last_shown_at)',
      );
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS concepts (
          concept_name TEXT PRIMARY KEY,
          description TEXT,
          key_points TEXT,
          source_deck_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
  }

  // ============ Deck 操作 ============

  Future<String> insertDeck(Deck deck) async {
    final db = await database;
    await db.insert('decks', deck.toMap());
    return deck.id;
  }

  Future<List<Deck>> getAllDecks() async {
    final db = await database;
    final maps = await db.query('decks', orderBy: 'created_at DESC');
    return maps.map(Deck.fromMap).toList();
  }

  Future<Deck?> getDeck(String id) async {
    final db = await database;
    final maps = await db.query('decks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Deck.fromMap(maps.first);
  }

  Future<void> updateDeck(Deck deck) async {
    final db = await database;
    await db.update('decks', deck.toMap(), where: 'id = ?', whereArgs: [deck.id]);
  }

  Future<void> deleteDeck(String id) async {
    final db = await database;
    await db.delete('questions', where: 'deck_id = ?', whereArgs: [id]);
    await db.delete('study_records', where: 'deck_id = ?', whereArgs: [id]);
    await db.delete('decks', where: 'id = ?', whereArgs: [id]);
  }

  // ============ Question 操作 ============

  Future<String> insertQuestion(Question question) async {
    final db = await database;
    final id = question.id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : question.id;
    final q = Question(
      id: id,
      deckId: question.deckId,
      type: question.type,
      content: question.content,
      options: question.options,
      answer: question.answer,
      explanation: question.explanation,
      matchLeft: question.matchLeft,
      matchRight: question.matchRight,
      difficulty: question.difficulty,
      cognitiveLevel: question.cognitiveLevel,
    );
    await db.insert('questions', q.toMap());
    return id;
  }

  Future<List<Question>> getQuestionsByDeck(String deckId) async {
    final db = await database;
    final maps = await db.query('questions', where: 'deck_id = ?', whereArgs: [deckId]);
    return maps.map(Question.fromMap).toList();
  }

  // ============ 随机抽题 ============

  /// 获取所有题目（跨题包）
  Future<List<Question>> getAllQuestions() async {
    final db = await database;
    final maps = await db.query('questions');
    return maps.map(Question.fromMap).toList();
  }

  /// 随机抽取指定数量的题目
  Future<List<Question>> getRandomQuestions(int count) async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT * FROM questions ORDER BY RANDOM() LIMIT ?',
      [count],
    );
    return maps.map(Question.fromMap).toList();
  }

  /// 智能抽题：优先抽所属概念今日到期的题，其次未做过的，最后最久没做的。
  /// 排除冷却期内（last_shown_at > now - cooldown）的题，避免短期重复。
  /// ponytail: 题目无 concept 列，通过 deck_id → decks.concepts(逗号拼接)
  /// 关联概念，所以应用层两步：先拿 due concepts 反查 due deck_ids，再一条
  /// SQL 排序抽题。不是 N+1。
  Future<List<Question>> getSmartRandomQuestions(
    int count, {
    Duration cooldown = const Duration(hours: 12),
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = now - cooldown.inMilliseconds;

    // 1) due concepts → due deck_ids（decks.concepts 是逗号拼接，内存过滤）
    final dueNames = await getDueConceptNames();
    final Set<String> dueDeckIds = {};
    if (dueNames.isNotEmpty) {
      final dueSet = dueNames.toSet();
      final decks = await db.query('decks', columns: ['id', 'concepts']);
      for (final d in decks) {
        final raw = d['concepts'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final concepts = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        if (concepts.any((c) => dueSet.contains(c))) {
          dueDeckIds.add(d['id'] as String);
        }
      }
    }

    // 2) 单条 SQL 排序：due 优先 > 未做过 > 最久没做；排除冷却期内
    final dueDeckList = dueDeckIds.isEmpty ? null : dueDeckIds.toList();
    final args = <Object?>[];
    String dueOrder = '1';
    if (dueDeckList != null) {
      final placeholders = List.filled(dueDeckList.length, '?').join(',');
      dueOrder = 'CASE WHEN deck_id IN ($placeholders) THEN 0 ELSE 1 END';
      args.addAll(dueDeckList);
    }
    args.add(cooldownMs);
    args.add(count);

    final maps = await db.rawQuery(
      '''
      SELECT * FROM questions
      WHERE last_shown_at IS NULL OR last_shown_at <= ?
      ORDER BY
        $dueOrder,
        CASE WHEN last_shown_at IS NULL THEN 0 ELSE 1 END,
        last_shown_at ASC,
        RANDOM()
      LIMIT ?
      ''',
      args,
    );
    return maps.map(Question.fromMap).toList();
  }

  /// 记录题目展示与判题结果（用于冷却去重）
  Future<void> recordQuestionShown(String questionId, {required bool correct}) async {
    final db = await database;
    await db.update(
      'questions',
      {
        'last_shown_at': DateTime.now().millisecondsSinceEpoch,
        'last_result': correct ? 'correct' : 'wrong',
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  // ============ StudyRecord 操作 ============

  Future<void> upsertStudyRecord(StudyRecord record) async {
    final db = await database;
    await db.insert('study_records', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<StudyRecord?> getStudyRecord(String deckId) async {
    final db = await database;
    final maps = await db.query('study_records', where: 'deck_id = ?', whereArgs: [deckId]);
    if (maps.isEmpty) return null;
    return StudyRecord.fromMap(maps.first);
  }

  // ============ UserStats 操作 ============

  Future<UserStats> getUserStats() async {
    final db = await database;
    final maps = await db.query('user_stats', where: 'id = 1');
    if (maps.isEmpty) {
      return UserStats(lastStudyDate: DateTime.now());
    }
    return UserStats.fromMap(maps.first);
  }

  Future<void> updateUserStats(UserStats stats) async {
    final db = await database;
    await db.update('user_stats', stats.toMap(), where: 'id = 1');
  }

  // ============ ConceptMastery 操作 ============

  /// 获取概念掌握度
  Future<Map<String, dynamic>?> getConceptMastery(String conceptName) async {
    final db = await database;
    final maps = await db.query(
      'concept_mastery',
      where: 'concept_name = ?',
      whereArgs: [conceptName],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// 更新概念掌握度
  Future<void> updateConceptMastery(
    String conceptName, {
    required double easeFactor,
    required int intervalDays,
    required int repetitions,
    int? nextReviewDate,
    String? lastResult,
  }) async {
    final db = await database;
    await db.insert('concept_mastery', {
      'concept_name': conceptName,
      'ease_factor': easeFactor,
      'interval_days': intervalDays,
      'repetitions': repetitions,
      'next_review_date': nextReviewDate,
      'last_result': lastResult,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取今日应复习的概念
  Future<List<String>> getDueConceptNames() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      'concept_mastery',
      where: 'next_review_date IS NOT NULL AND next_review_date <= ?',
      whereArgs: [now],
      columns: ['concept_name'],
    );
    return maps.map((m) => m['concept_name'] as String).toList();
  }

  /// 获取所有已追踪的概念名称
  Future<List<String>> getTrackedConceptNames() async {
    final db = await database;
    final maps = await db.query('concept_mastery', columns: ['concept_name']);
    return maps.map((m) => m['concept_name'] as String).toList();
  }

  /// 获取所有概念掌握度信息（按更新时间倒序）
  Future<List<Map<String, dynamic>>> getAllConceptMastery() async {
    final db = await database;
    return db.query('concept_mastery', orderBy: 'updated_at DESC');
  }

  /// 删除学习记录（题包删除时同步删除）
  Future<void> deleteConceptMastery(String conceptName) async {
    final db = await database;
    await db.delete('concept_mastery', where: 'concept_name = ?', whereArgs: [conceptName]);
  }

  // ============ Concept 定义 ============

  /// 获取概念定义（含 description / keyPoints）
  Future<Map<String, dynamic>?> getConcept(String conceptName) async {
    final db = await database;
    final maps = await db.query(
      'concepts',
      where: 'concept_name = ?',
      whereArgs: [conceptName],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final m = maps.first;
    return {
      'concept_name': m['concept_name'] as String,
      'description': m['description'] as String?,
      'key_points': m['key_points'] != null
          ? (jsonDecode(m['key_points'] as String) as List<dynamic>).cast<String>()
          : <String>[],
      'source_deck_id': m['source_deck_id'] as String?,
    };
  }

  /// 写入/更新概念定义（深度模式 Phase 1.5 或 AI 懒生成调用）
  Future<void> upsertConcept(
    String conceptName, {
    String? description,
    List<String>? keyPoints,
    String? sourceDeckId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('concepts', {
      'concept_name': conceptName,
      'description': description,
      'key_points': keyPoints != null ? jsonEncode(keyPoints) : null,
      'source_deck_id': sourceDeckId,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// Web 平台内存数据库（sqflite 不支持 web）
class _WebDatabase implements Database {
  final Map<String, List<Map<String, dynamic>>> _tables = {};

  @override
  Future<int> insert(String table, Map<String, dynamic> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    _tables.putIfAbsent(table, () => []);
    _tables[table]!.add(Map<String, dynamic>.from(values));
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    final rows = List<Map<String, dynamic>>.from(_tables[table] ?? []);
    if (orderBy != null && orderBy.contains('DESC')) {
      rows.sort((a, b) => (b['created_at'] ?? 0).compareTo(a['created_at'] ?? 0));
    }
    if (limit != null && limit < rows.length) {
      return rows.sublist(0, limit);
    }
    return rows;
  }

  @override
  Future<int> update(String table, Map<String, dynamic> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    return 0;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    if (where == null) {
      _tables[table] = [];
    }
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    return [];
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => 1;

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<QueryCursor> queryCursor(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset, int? bufferSize}) async {
    final rows = await query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs, groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);
    return _WebQueryCursor(rows);
  }

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) async {
    return _WebQueryCursor([]);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<int> getVersion() async => 2;

  @override
  Future<void> close() async {}

  @override
  String get path => ':memory:';

  @override
  bool get isOpen => true;

  @override
  Database get database => this;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WebQueryCursor implements QueryCursor {
  final List<Map<String, dynamic>> _rows;
  int _index = -1;

  _WebQueryCursor(this._rows);

  @override
  Future<bool> moveNext() async => ++_index < _rows.length;

  @override
  Map<String, dynamic> get current => _rows[_index];

  @override
  Future<bool> movePrevious() async => --_index >= 0;

  @override
  Future<bool> moveTo(int index) async {
    _index = index;
    return _index >= 0 && _index < _rows.length;
  }

  @override
  Future<bool> moveToFirst() async {
    _index = _rows.isEmpty ? -1 : 0;
    return _index == 0;
  }

  @override
  Future<bool> moveToLast() async {
    _index = _rows.length - 1;
    return _index >= 0;
  }

  @override
  Future<void> close() async {}

  @override
  int get length => _rows.length;
}
