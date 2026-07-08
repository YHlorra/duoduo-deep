/// 用户学习目的 — 深度模式输入
class LearningGoal {
  final String purpose;       // 必填: "我想学 Python 入门，为了做数据分析"
  final String level;         // 'beginner' | 'intermediate' | 'advanced'
  final List<String> urls;    // 用户提供的 URL 列表（可选）
  final String extraText;     // 补充文本（可选）

  const LearningGoal({
    required this.purpose,
    this.level = 'intermediate',
    this.urls = const [],
    this.extraText = '',
  });

  /// 水平中文标签
  String get levelLabel {
    switch (level) {
      case 'beginner': return '入门';
      case 'advanced': return '高级';
      default: return '进阶';
    }
  }
}
