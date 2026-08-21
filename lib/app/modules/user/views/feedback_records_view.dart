import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/app_tag.dart';
import '../../../routes/app_pages.dart';

// 反馈记录列表页面
class FeedbackRecordsView extends StatelessWidget {
  const FeedbackRecordsView({Key? key}) : super(key: key);

  // 固定数据
  List<Map<String, dynamic>> get _feedbackRecords => [
    {
      'id': 1,
      'type': '课程内容',
      'subject': '中级经济 - 基础科目',
      'description': '课程视频播放卡顿，影响学习体验，希望能够优化视频加载速度。',
      'images': <String>[],
      'status': '已回复',
      'createTime': '2026-06-04 14:30',
      'reply': '感谢您的反馈，我们已优化视频服务器，问题已解决。',
      'replyTime': '2026-06-05 10:00',
    },
    {
      'id': 2,
      'type': '试题内容',
      'subject': '中级经济 - 专业知识与实践',
      'description': '第35题答案有误，正确答案应该是B选项，请核实。',
      'images': <String>[],
      'status': '处理中',
      'createTime': '2026-06-05 09:15',
      'reply': '',
      'replyTime': '',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: const CommonAppBar(title: '反馈记录'),
      body: ListView.builder(
        padding: EdgeInsets.all(ScreenAdapter.width(32)),
        itemCount: _feedbackRecords.length,
        itemBuilder: (context, index) {
          final record = _feedbackRecords[index];
          return _buildRecordItem(context, record);
        },
      ),
    );
  }

  Widget _buildRecordItem(BuildContext context, Map<String, dynamic> record) {
    final status = record['status'] as String;
    final isReplied = status == '已回复';

    return GestureDetector(
      onTap: () {
        Get.toNamed(Routes.FEEDBACK_RECORD_DETAIL, arguments: record);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: ScreenAdapter.height(24)),
        padding: EdgeInsets.all(ScreenAdapter.width(32)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1A000000),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：类型 + 状态
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppTag(
                  record['type'],
                  bgColor: const Color(0xFFEBF2FF),
                  fontSize: ScreenAdapter.fontSize(24),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(16),
                    vertical: ScreenAdapter.height(8),
                  ),
                ),
                AppTag(
                  status,
                  bgColor: isReplied
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  textColor: isReplied
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFF9800),
                  fontSize: ScreenAdapter.fontSize(24),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(16),
                    vertical: ScreenAdapter.height(8),
                  ),
                ),
              ],
            ),
            SizedBox(height: ScreenAdapter.height(20)),
            // 科目
            Text(
              record['subject'],
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(28),
                color: const Color(0xFF666666),
              ),
            ),
            SizedBox(height: ScreenAdapter.height(12)),
            // 描述
            Text(
              record['description'],
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(30),
                color: const Color(0xFF333333),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: ScreenAdapter.height(20)),
            // 时间
            Text(
              record['createTime'],
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(24),
                color: const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
