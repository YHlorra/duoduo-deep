/// 题包模型 - 一条内容拆解出的题目集合
class Deck {
  final String id;
  final String title;
  final String? sourceText;
  final String? sourceUrl;
  final String? sourceImage;
  final List<String> concepts;
  final int questionCount;
  final int masteryLevel; // 0-100
  final DateTime createdAt;
  final DateTime updatedAt;

  Deck({
    required this.id,
    required this.title,
    this.sourceText,
    this.sourceUrl,
    this.sourceImage,
    this.concepts = const [],
    this.questionCount = 0,
    this.masteryLevel = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Deck copyWith({
    String? id,
    String? title,
    String? sourceText,
    String? sourceUrl,
    String? sourceImage,
    List<String>? concepts,
    int? questionCount,
    int? masteryLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceText: sourceText ?? this.sourceText,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceImage: sourceImage ?? this.sourceImage,
      concepts: concepts ?? this.concepts,
      questionCount: questionCount ?? this.questionCount,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'source_text': sourceText,
      'source_url': sourceUrl,
      'source_image': sourceImage,
      'concepts': concepts.join(','),
      'question_count': questionCount,
      'mastery_level': masteryLevel,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Deck.fromMap(Map<String, dynamic> map) {
    return Deck(
      id: map['id'] as String,
      title: map['title'] as String,
      sourceText: map['source_text'] as String?,
      sourceUrl: map['source_url'] as String?,
      sourceImage: map['source_image'] as String?,
      concepts: (map['concepts'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? const [],
      questionCount: (map['question_count'] as int?) ?? 0,
      masteryLevel: (map['mastery_level'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
