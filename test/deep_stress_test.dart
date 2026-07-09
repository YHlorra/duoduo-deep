import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dlg_q/features/deep/deep_pipeline_controller.dart';
import 'package:dlg_q/features/deep/tools/learning_goal.dart';
import 'package:dlg_q/services/content_analyzer.dart';
import 'package:dlg_q/services/log_service.dart';
import 'package:dlg_q/services/openai_service.dart';

const _apiKey = String.fromEnvironment('API_KEY');
const _apiModel = String.fromEnvironment('API_MODEL', defaultValue: 'gpt-4o-mini');
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.openai.com/v1');

void main() {
  // Skip all stress tests if no API key is configured (e.g. in CI)
  if (_apiKey.isEmpty) {
    test('stress tests skipped (no API_KEY)', () {
      expect(true, isTrue);
    });
    return;
  }

  late OpenAIService openai;
  late ContentAnalyzer analyzer;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'ai_api_key': _apiKey,
      'ai_model': _apiModel,
      'ai_base_url': _apiBaseUrl,
    });
    openai = OpenAIService();
    analyzer = ContentAnalyzer(openai);
    LogService.instance.setCapacity(500);
  });

  group('DeepPipeline stress test', () {
    final testCases = [
      LearningGoal(purpose: 'Python beginner', level: 'beginner'),
      LearningGoal(purpose: 'Machine learning neural networks', level: 'advanced'),
      LearningGoal(
        purpose: 'Quantum computing basics',
        level: 'intermediate',
        extraText: 'Quantum computing uses qubits.',
      ),
      LearningGoal(
        purpose: 'How to make pour-over coffee',
        level: 'beginner',
        extraText: 'Water temperature 90-96C.',
      ),
      LearningGoal(purpose: 'Blockchain consensus mechanisms', level: 'advanced'),
    ];

    for (var i = 0; i < testCases.length; i++) {
      final goal = testCases[i];
      test('deep case $i', () async {
        final controller = DeepPipelineController(openai);
        LogService.instance.log('test', 'info', 'test_case_start', {
          'case': i,
          'purpose': goal.purpose,
          'level': goal.level,
        });

        await controller.run(goal);

        final state = controller.state;
        LogService.instance.log('test', 'info', 'test_case_end', {
          'case': i,
          'stage': state.stage.name,
          'error': state.error,
          'questionCount': state.result?.questions.length,
          'conceptCount': state.result?.conceptNames.length,
        });

        expect(state.stage, PipelineStage.done,
            reason: 'Case $i failed: ${state.error}');
        expect(state.result, isNotNull, reason: 'Case $i returned null result');
        expect(state.result!.questions, isNotEmpty,
            reason: 'Case $i returned empty questions');
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  });

  group('ContentAnalyzer stress test', () {
    final testTexts = [
      'Python is a high-level programming language created by Guido van Rossum in 1991. It has a concise syntax and powerful standard library.',
      'Photosynthesis is the process by which plants convert carbon dioxide and water into glucose and oxygen using light energy.',
      'Special relativity was proposed by Einstein in 1905. Two postulates: physical laws are the same in all inertial frames; speed of light is constant.',
    ];

    for (var i = 0; i < testTexts.length; i++) {
      final text = testTexts[i];
      test('analyze case $i', () async {
        LogService.instance.log('test', 'info', 'analyze_start', {'case': i});

        final result = await analyzer.analyze(text: text);

        LogService.instance.log('test', 'info', 'analyze_end', {
          'case': i,
          'questionCount': result.questions.length,
          'conceptCount': result.conceptNames.length,
          'title': result.title,
        });

        expect(result.questions, isNotEmpty, reason: 'Analyze case $i returned empty');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}
