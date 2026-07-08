import 'package:shared_preferences/shared_preferences.dart';

/// 学习偏好设置
class AppPrefs {
  final String pace;       // 'relaxed' | 'normal' | 'intensive'
  final String depth;      // 'surface' | 'standard' | 'deep'
  final String format;     // 'mixed' | 'choice' | 'fillblank'
  final String language;   // 'zh' | 'en' | 'ja'

  const AppPrefs({
    this.pace = 'normal',
    this.depth = 'standard',
    this.format = 'mixed',
    this.language = 'zh',
  });

  static Future<AppPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPrefs(
      pace: prefs.getString('prefs_pace') ?? 'normal',
      depth: prefs.getString('prefs_depth') ?? 'standard',
      format: prefs.getString('prefs_format') ?? 'mixed',
      language: prefs.getString('prefs_language') ?? 'zh',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prefs_pace', pace);
    await prefs.setString('prefs_depth', depth);
    await prefs.setString('prefs_format', format);
    await prefs.setString('prefs_language', language);
  }

  AppPrefs copyWith({
    String? pace,
    String? depth,
    String? format,
    String? language,
  }) {
    return AppPrefs(
      pace: pace ?? this.pace,
      depth: depth ?? this.depth,
      format: format ?? this.format,
      language: language ?? this.language,
    );
  }
}
