import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import 'tools/learning_goal.dart';

class GoalCollectionScreen extends ConsumerStatefulWidget {
  final void Function(LearningGoal goal) onStart;
  final String? initialUrl;

  const GoalCollectionScreen({super.key, required this.onStart, this.initialUrl});

  @override
  ConsumerState<GoalCollectionScreen> createState() =>
      _GoalCollectionScreenState();
}

class _GoalCollectionScreenState extends ConsumerState<GoalCollectionScreen> {
  final _purposeController = TextEditingController();
  final _extraController = TextEditingController();
  final List<TextEditingController> _urlControllers = [TextEditingController()];
  String _level = 'intermediate';

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlControllers[0].text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _purposeController.dispose();
    _extraController.dispose();
    for (final c in _urlControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addUrlField() {
    setState(() {
      _urlControllers.add(TextEditingController());
    });
  }

  void _removeUrlField(int index) {
    if (_urlControllers.length <= 1) return;
    setState(() {
      _urlControllers[index].dispose();
      _urlControllers.removeAt(index);
    });
  }

  List<String> get _urls =>
      _urlControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  void _submit() {
    final purpose = _purposeController.text.trim();
    if (purpose.isEmpty) return;

    final goal = LearningGoal(
      purpose: purpose,
      level: _level,
      urls: _urls,
      extraText: _extraController.text.trim(),
    );
    widget.onStart(goal);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _purposeController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          '深度拆解',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 学习目的
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '学习目的',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _purposeController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '例如：我想学习Python入门，为了做数据分析',
                        hintStyle: const TextStyle(color: AppColors.textLight),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 水平选择
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '当前水平',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildLevelChip('入门', 'beginner'),
                        const SizedBox(width: 10),
                        _buildLevelChip('进阶', 'intermediate'),
                        const SizedBox(width: 10),
                        _buildLevelChip('高级', 'advanced'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // URL 列表
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '参考链接',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addUrlField,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_urlControllers.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlControllers[i],
                                decoration: InputDecoration(
                                  hintText: 'https://example.com',
                                  hintStyle:
                                      const TextStyle(color: AppColors.textLight),
                                  filled: true,
                                  fillColor: AppColors.surface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            if (_urlControllers.length > 1)
                              IconButton(
                                onPressed: () => _removeUrlField(i),
                                icon: const Icon(Icons.close_rounded,
                                    size: 20, color: AppColors.textLight),
                                padding: const EdgeInsets.only(left: 8),
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 补充文本
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '补充说明（可选）',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _extraController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '其他想告诉 AI 的信息...',
                        hintStyle: const TextStyle(color: AppColors.textLight),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // 提交按钮
              ElevatedButton(
                onPressed: canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit ? AppColors.green : AppColors.border,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '开始深度拆解',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildLevelChip(String label, String value) {
    final selected = _level == value;
    return GestureDetector(
      onTap: () => setState(() => _level = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
