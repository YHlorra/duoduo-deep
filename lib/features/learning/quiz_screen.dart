import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/providers.dart';
import '../../data/models/question.dart';
import '../../data/models/question_type.dart';
import '../../shared/widgets/duo_button.dart';
import '../../shared/widgets/stats_widgets.dart';
import 'widgets/question_widgets.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final String? deckId;
  final List<Question>? questions;

  const QuizScreen({super.key, this.deckId, this.questions});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  List<Question> _questions = [];
  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _showResult = false;
  bool _isLoading = true;
  int _correctCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    // 随机模式直接传入题目
    if (widget.questions != null) {
      setState(() {
        _questions = widget.questions!;
        _isLoading = false;
      });
      return;
    }
    if (widget.deckId == null) {
      setState(() => _isLoading = false);
      return;
    }
    final db = ref.read(databaseProvider);
    final questions = await db.getQuestionsByDeck(widget.deckId!);
    setState(() {
      _questions = questions;
      _isLoading = false;
    });
  }

  void _checkAnswer() {
    if (_selectedAnswer == null) return;

    final question = _questions[_currentIndex];
    final isCorrect = _checkCorrect(question, _selectedAnswer!);

    setState(() {
      _showResult = true;
      if (isCorrect) {
        _correctCount++;
        ref.read(userStatsProvider.notifier).onCorrect();
      } else {
        ref.read(userStatsProvider.notifier).onWrong();
      }
    });
  }

  bool _checkCorrect(Question question, String answer) {
    switch (question.type) {
      case QuestionType.multipleChoice:
      case QuestionType.trueFalse:
        return answer.trim() == question.answer.trim();
      case QuestionType.fillBlank:
        // 去除空格和标点，忽略大小写
        return answer.trim().toLowerCase() == question.answer.trim().toLowerCase();
      case QuestionType.matching:
      case QuestionType.ordering:
        // 对于匹配和排序，答案格式为 "item1-match1|item2-match2" 或 "step1|step2|step3"
        // 比较时需要规范化
        final normalize = (String s) => s.split('|').map((e) => e.trim()).join('|');
        return normalize(answer) == normalize(question.answer);
    }
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _showResult = false;
      });
    } else {
      // 完成
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final allCorrect = _correctCount == _questions.length;
    await ref.read(userStatsProvider.notifier).onDeckComplete(allCorrect: allCorrect);
    // 仅知识点模式（有 deckId）才保存学习记录
    if (widget.deckId != null) {
      await ref.read(deckOperationsProvider).saveStudyRecord(
            widget.deckId!,
            _correctCount,
            _questions.length,
          );
    }
    setState(() => _isComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.green)),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('答题')),
        body: const Center(child: Text('此题包暂无题目')),
      );
    }

    if (_isComplete) {
      return _buildResultScreen();
    }

    final stats = ref.watch(userStatsProvider);
    final question = _questions[_currentIndex];
    final isCorrect = _showResult && _checkCorrect(question, _selectedAnswer ?? '');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 进度条
            stats.when(
              data: (s) => QuizProgressBar(
                progress: (_currentIndex + 1) / _questions.length,
                hearts: s.hearts,
              ),
              loading: () => const SizedBox(height: 40),
              error: (_, __) => const SizedBox(height: 40),
            ),
            // 题目内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 题型标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        question.type.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 题干
                    Text(
                      question.type == QuestionType.fillBlank
                          ? '填入正确答案'
                          : question.content,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 答题区
                    QuestionWidget(
                      question: question,
                      showResult: _showResult,
                      selectedAnswer: _selectedAnswer,
                      onAnswerSelected: (answer) {
                        setState(() => _selectedAnswer = answer);
                      },
                    ),
                    // 解析
                    if (_showResult && question.explanation != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isCorrect ? Icons.lightbulb : Icons.info,
                                  size: 18,
                                  color: isCorrect ? AppColors.green : AppColors.blue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '解析',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isCorrect ? AppColors.green : AppColors.blue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              question.explanation!,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 底部操作区
            _buildBottomBar(isCorrect),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isCorrect) {
    if (!_showResult) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border, width: 2)),
        ),
        child: SafeArea(
          child: DuoButton(
            label: '检查',
            color: AppColors.green,
            enabled: _selectedAnswer != null,
            width: double.infinity,
            onPressed: _checkAnswer,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect ? AppColors.greenLight : AppColors.redLight,
        border: Border(
          top: BorderSide(
            color: isCorrect ? AppColors.green : AppColors.red,
            width: 2,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? '答对了！' : '答错了',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isCorrect ? AppColors.greenDark : AppColors.redDark,
                    ),
                  ),
                  if (!isCorrect) ...[
                    const SizedBox(height: 4),
                    Text(
                      '正确答案: ${_questions[_currentIndex].answer}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.redDark,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            DuoButton(
              label: _currentIndex < _questions.length - 1 ? '继续' : '完成',
              color: isCorrect ? AppColors.green : AppColors.red,
              width: 140,
              height: 56,
              fontSize: 18,
              onPressed: _nextQuestion,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultScreen() {
    final accuracy = _questions.isNotEmpty ? _correctCount / _questions.length : 0.0;
    final allCorrect = _correctCount == _questions.length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 结果图标
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: allCorrect ? AppColors.gold : AppColors.green,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  allCorrect ? Icons.emoji_events : Icons.check_circle,
                  size: 60,
                  color: Colors.white,
                ),
              ).animate().scale(duration: 500.ms),
              const SizedBox(height: 24),
              Text(
                allCorrect ? '完美！' : '完成！',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: allCorrect ? AppColors.gold : AppColors.green,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '答对 $_correctCount / ${_questions.length} 题',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              // 统计卡片
              Row(
                children: [
                  _ResultCard(
                    icon: Icons.star,
                    color: AppColors.gold,
                    label: 'XP',
                    value: '+${_correctCount * 10 + (allCorrect ? 100 : 50)}',
                  ),
                  const SizedBox(width: 12),
                  _ResultCard(
                    icon: Icons.check_circle,
                    color: AppColors.green,
                    label: '正确率',
                    value: '${(accuracy * 100).round()}%',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              DuoButton(
                label: '返回',
                color: AppColors.blue,
                width: double.infinity,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _ResultCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
