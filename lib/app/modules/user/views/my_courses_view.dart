import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/course_card.dart';
import '../../../routes/app_pages.dart';
import '../controllers/my_courses_controller.dart';

class MyCoursesView extends GetView<MyCoursesController> {
  const MyCoursesView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: CommonAppBar(
        title: '我的课程',
        titleStyle: TextStyle(
          fontSize: ScreenAdapter.fontSize(44),
          fontWeight: FontWeight.w500,
          color: const Color(0xFF333333),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.courseOrderList.isEmpty) {
          return Center(
            child: CircularProgressIndicator(),
          );
        }

        if (controller.courseOrderList.isEmpty) {
          return CommonEmptyState(
            icon: Icons.school_outlined,
            title: '还没有课程哦，去看看吧',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.onRefresh,
          child: ListView.builder(
            controller: controller.scrollController,
            physics:
                AlwaysScrollableScrollPhysics(), // 确保即使内容不足也能触发下拉刷新
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(46),
              vertical: ScreenAdapter.height(32),
            ),
            itemCount: controller.courseOrderList.length + 1,
            itemBuilder: (context, index) {
              if (index == controller.courseOrderList.length) {
                return _buildLoadMoreFooter();
              }

              final orderItem = controller.courseOrderList[index];
              // 课程数据在 course 嵌套字段中,合并订单级别信息
              final course = orderItem['course'] as Map<String, dynamic>? ??
                  <String, dynamic>{};
              final courseData = Map<String, dynamic>.from(course);
              courseData['is_expired'] = orderItem['is_expired'];
              courseData['order_status_text'] = orderItem['order_status_text'];
              courseData['start_time_text'] = orderItem['start_time_text'];
              courseData['end_time_text'] = orderItem['end_time_text'];
              // 科目名(subject_name 是订单项顶层字段,卡片标题下方展示)
              courseData['subject_name'] = orderItem['subject_name'];
              // ★详情接口传参:order_id + subject_id(三级科目,覆盖 course 嵌套里的 subject_id)
              courseData['order_id'] = orderItem['order_id'];
              courseData['subject_id'] = orderItem['subject_id'];

              return CourseCard(
                course: courseData,
                onTap: () {
                  // 已购课程进入「我的课程详情」(目录/资料 + 页内播放)
                  Get.toNamed(Routes.MY_COURSE_DETAIL, arguments: courseData);
                },
                coverLayout: true,
                buttonText: '开始学习',
              );
            },
          ),
        );
      }),
    );
  }

  Widget _buildLoadMoreFooter() {
    return Obx(() {
      if (controller.isLoadingMore.value) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(24)),
          child: Center(
            child: SizedBox(
              width: ScreenAdapter.width(36),
              height: ScreenAdapter.width(36),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(24)),
          child: Center(
            child: Text(
              '没有更多了',
              style: TextStyle(
                color: Colors.grey,
                fontSize: ScreenAdapter.fontSize(28),
              ),
            ),
          ),
        );
      }

      return SizedBox(height: ScreenAdapter.height(12));
    });
  }
}
