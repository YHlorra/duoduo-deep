import 'question_type.dart';

/// 题目模型
class Question {
  final String id;
  final String deckId;
  final QuestionType type;
  final String content; // 题干
  final List<String> options; // 选项(选择题/判断题/排序题用)
  final String answer; // 正确答案
  final String? explanation; // 解析
  // 匹配题专用: 左右两列
  final List<String>? matchLeft;
  final List<String>? matchRight;
  final String? difficulty; // 'easy' | 'medium' | 'hard'
  final String? cognitiveLevel; // 'knowledge' | 'skill'

  Question({
    required this.id,
    required this.deckId,
    required this.type,
    required this.content,
    this.options = const [],
    required this.answer,
    this.explanation,
    this.matchLeft,
    this.matchRight,
    this.difficulty,
    this.cognitiveLevel,
  });

  /// Resolves [answer] to the matching option text when the LLM emitted a
  /// letter index (A/B/C/...) instead of the full option string. Required
  /// because the deck JSON schema declares `answer` as plain `string` with no
  /// `enum` constraint over `options`, and the generator prompt's example
  /// nudges the model toward letter-style output.
  ///
  /// Returns the raw [answer] unchanged for non multi-choice types and when
  /// the value is already full text (or a letter outside the option range).
  String get resolvedAnswer {
    final raw = answer.trim();
    if (raw.isEmpty) return answer;
    final isMulti = type == QuestionType.multipleChoice ||
        type == QuestionType.trueFalse;
    if (!isMulti || options.isEmpty || raw.length != 1) return answer;
    final upper = raw.toUpperCase();
    final code = upper.codeUnitAt(0);
    if (code < 65 || code > 90) return answer;
    final idx = code - 65;
    if (idx >= options.length) return answer;
    return options[idx];
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deck_id': deckId,
      'type': type.value,
      'content': content,
      'options': options.join('\x00'),
      'answer': answer,
      'explanation': explanation,
      'match_left': matchLeft?.join('\x00'),
      'match_right': matchRight?.join('\x00'),
      'difficulty': difficulty,
      'cognitive_level': cognitiveLevel,
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as String,
      deckId: map['deck_id'] as String,
      type: QuestionType.fromString(map['type'] as String),
      content: map['content'] as String,
      options: (map['options'] as String?)?.split('\x00').where((s) => s.isNotEmpty).toList() ?? [],
      answer: map['answer'] as String,
      explanation: map['explanation'] as String?,
      matchLeft: (map['match_left'] as String?)?.split('\x00').where((s) => s.isNotEmpty).toList(),
      matchRight: (map['match_right'] as String?)?.split('\x00').where((s) => s.isNotEmpty).toList(),
      difficulty: map['difficulty'] as String?,
      cognitiveLevel: map['cognitive_level'] as String?,
    );
  }

  /// 从 OpenAI 返回的 JSON 构建
  factory Question.fromJson(Map<String, dynamic> json, String deckId) {
    final type = QuestionType.fromString(json['type'] as String? ?? 'multiple_choice');
    final options = (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final matchLeft = (json['match_left'] as List<dynamic>?)?.map((e) => e.toString()).toList();
    final matchRight = (json['match_right'] as List<dynamic>?)?.map((e) => e.toString()).toList();

    return Question(
      id: '',
      deckId: deckId,
      type: type,
      content: json['content'] as String? ?? '',
      options: options,
      answer: json['answer']?.toString() ?? '',
      explanation: json['explanation'] as String?,
      matchLeft: matchLeft,
      matchRight: matchRight,
      difficulty: json['difficulty'] as String?,
      cognitiveLevel: json['cognitive_level'] as String?,
    );
  }
}
