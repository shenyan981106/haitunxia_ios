part of 'question_train_controller.dart';

// ===== 答题卡/退出弹窗 Widget 构建(mixin) =====
// ★2026-08-26 自 question_train_controller.dart 机械拆出,逻辑零改动

mixin _QuestionTrainUi {
  // ===== 以下抽象成员由 QuestionTrainController 实现(拆分时声明,勿删) =====
  RxList<Question> get questions;
  PageController get pageController;
  RxMap<int, List<int>> get userAnswers;
  RxMap<int, bool> get answerResults;
  RxInt get currentQuestionIndex;
  RxString get pageMode;
  RxBool get isDarkMode;
  RxBool get showExplanation;
  Future<void> submitExam({bool auto = false});
  void jumpToQuestion(int index) {
    if (index >= 0 && index < questions.length) {
      pageController.jumpToPage(index);
      // updateCurrentIndex 会被 PageView 触发，所以这里不需要手动调用
    }
  }

  // (底部弹出 (底部弹出)
  void showAnswerCard() {
    final context = Get.context;
    if (context == null) return;

    Get.bottomSheet(
      _buildAnswerCardContent(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
    );
  }

  // 答题卡内容
  Widget _buildAnswerCardContent() {
    final isDark = isDarkMode.value;

    return Obx(() => Container(
          constraints: BoxConstraints(
            maxHeight: Get.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ScreenAdapter.radius(32))),
          ),
          padding: EdgeInsets.all(ScreenAdapter.width(32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条
              Container(
                width: ScreenAdapter.width(120),
                height: ScreenAdapter.height(8),
                margin: EdgeInsets.only(bottom: ScreenAdapter.height(30)),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF555555) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(ScreenAdapter.radius(4)),
                ),
              ),

              // 顶部标题和关闭按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: ScreenAdapter.width(48)), // 占位，让标题居中
                  Text(
                    '答题卡',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(46),
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Icon(Icons.close,
                        color: isDark ? Colors.white : Colors.black87,
                        size: ScreenAdapter.width(60)),
                  ),
                ],
              ),

              // 题目网格（每行5个，最多显示6行题目编号）
              SizedBox(
                height: _calcGridHeight(),
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 根据可用宽度精确计算每行高度
                      final crossAxisCount = 5;
                      final spacing = 10.0;
                      final crossAxisSpacing = 12.0;
                      final aspectRatio = 1.15;
                      final availableWidth = constraints.maxWidth;
                      final itemWidth = (availableWidth -
                              crossAxisSpacing * (crossAxisCount - 1)) /
                          crossAxisCount;
                      final itemHeight = itemWidth / aspectRatio;
                      final rowHeight = itemHeight + spacing;

                      return GridView.builder(
                        shrinkWrap: questions.length <= 30,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: crossAxisSpacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
                          mainAxisExtent: itemHeight,
                        ),
                        itemCount: questions.length,
                        itemBuilder: (context, index) {
                          bool isCurrent = currentQuestionIndex.value == index;
                          bool isAnswered = userAnswers.containsKey(index) &&
                              (userAnswers[index]?.isNotEmpty ?? false);
                          bool? isCorrect = answerResults[index];
                          final question = questions[index];
                          final questionStatus = question.questionStatus;

                          Color bgColor =
                              isDark ? const Color(0xFF3D3D3D) : Colors.white;
                          Color borderColor = isDark
                              ? const Color(0xFF555555)
                              : Colors.grey[300]!;
                          Color textColor =
                              isDark ? Colors.white70 : Colors.black87;

                          // 优先根据 questionStatus 判断颜色
                          if (questionStatus == 2) {
                            // 已做正确
                            bgColor = const Color(0xFF52C41A);
                            borderColor = bgColor;
                            textColor = Colors.white;
                          } else if (questionStatus == 3) {
                            // 已做错误
                            bgColor = const Color(0xFFF5222D);
                            borderColor = bgColor;
                            textColor = Colors.white;
                          } else if (isAnswered) {
                            // 已作答但没有 questionStatus 或 questionStatus 为未做
                            if (pageMode.value == 'TRAINING' &&
                                isCorrect != null &&
                                showExplanation.value) {
                              // 练习模式已查看结果，显示对错颜色（绿/红）
                              bgColor = isCorrect
                                  ? const Color(0xFF52C41A)
                                  : const Color(0xFFF5222D);
                              borderColor = bgColor;
                              textColor = Colors.white;
                            } else {
                              // 已作答但未查看结果，显示蓝底白字（实心）
                              bgColor = const Color(0xFF1890FF);
                              borderColor = bgColor;
                              textColor = Colors.white;
                            }
                          } else if (isCurrent) {
                            // 当前题目但未作答，显示蓝色边框+原底蓝字（空心，与已作答区分）
                            borderColor = const Color(0xFF1890FF);
                            textColor = const Color(0xFF1890FF);
                          }

                          return GestureDetector(
                            onTap: () {
                              jumpToQuestion(index);
                              Get.back();
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bgColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: borderColor,
                                    width: isCurrent ? 1.5 : 1.0),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: ScreenAdapter.fontSize(32),
                                  color: textColor,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // 提交按钮 (考试模式和练习模式都显示)
              if (pageMode.value == 'EXAM' || pageMode.value == 'TRAINING') ...[
                SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: ScreenAdapter.height(20)),
                      SizedBox(
                        width: double.infinity,
                        height: ScreenAdapter.height(128),
                        child: ElevatedButton(
                          onPressed: () {
                            Get.back();
                            submitExam();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1890FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ScreenAdapter.radius(60)),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            '提交',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(44),
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ));
  }

  // 计算网格高度：最多显示6行，不满6行按实际行数（无空白）
  double _calcGridHeight() {
    // 基于屏幕宽度计算每行实际高度（需扣除 Container 的 padding）
    final screenWidth = Get.width - ScreenAdapter.width(32) * 2;
    const crossAxisCount = 5;
    const crossAxisSpacing = 12.0;
    const spacing = 10.0;
    const aspectRatio = 1.15;

    final itemWidth = (screenWidth - crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final itemHeight = itemWidth / aspectRatio;
    final rowHeight = itemHeight + spacing;

    final totalRows = (questions.length / crossAxisCount).ceil();
    final displayRows = totalRows.clamp(1, 6);
    return rowHeight * displayRows;
  }

  // 构建图例项
  Widget _buildLegendItem(bool isDark, Color color, String label,
      {bool hasBorder = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ScreenAdapter.width(28),
          height: ScreenAdapter.width(28),
          decoration: BoxDecoration(
            color: hasBorder ? Colors.white : color,
            shape: BoxShape.circle,
            border: hasBorder
                ? Border.all(color: Colors.grey[400]!, width: 1.5)
                : null,
          ),
        ),
        SizedBox(width: ScreenAdapter.width(8)),
        Text(
          label,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(24),
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Future<bool> showExitDialog({String message = '确定退出吗？'}) async {
    final completer = Completer<bool>();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '退出提示',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF333333),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.back();
                        completer.complete(false);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.back();
                        completer.complete(true);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EF5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
      transitionDuration: Duration.zero,
    );

    return completer.future;
  }
}
