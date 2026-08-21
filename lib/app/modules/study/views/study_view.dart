import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/keepAliveWrapper.dart';
import '../controllers/study_controller.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/course_card.dart';

class StudyView extends GetView<StudyController> {
  const StudyView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return KeepAliveWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: CommonAppBar(
          title: '全部课程',
          titleStyle: TextStyle(
            fontSize: ScreenAdapter.fontSize(44),
            fontWeight: FontWeight.w500,
            color: const Color(0xFF333333),
          ),
        ),
        body: Column(
          children: [
            // 筛选栏
            _buildFilterBar(),

            // 课程列表
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.courseList.isEmpty) {
                  return Center(child: CircularProgressIndicator());
                }

                if (controller.courseList.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => controller.getCourseList(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.55,
                          child: const CommonEmptyState(
                            icon: Icons.library_books_outlined,
                            title: '暂无课程数据',
                            iconSize: 64,
                            titleFontSize: 32,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => controller.getCourseList(),
                  child: ListView.builder(
                    controller: controller.scrollController,
                    physics:
                        AlwaysScrollableScrollPhysics(), // 确保即使内容不足也能触发下拉刷新
                    padding: EdgeInsets.symmetric(
                      horizontal: ScreenAdapter.width(46),
                      vertical: ScreenAdapter.height(32),
                    ),
                    itemCount: controller.courseList.length + 1,
                    itemBuilder: (context, index) {
                      if (index == controller.courseList.length) {
                        return _buildLoadMoreFooter();
                      }

                      return CourseCard(
                        course: controller.courseList[index],
                        onTap: () => controller
                            .goToCourseDetail(controller.courseList[index]),
                        coverLayout: true,
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
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

  // 筛选栏
  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        vertical: ScreenAdapter.height(24),
        horizontal: ScreenAdapter.width(46),
      ),
      child: Obx(() => Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(controller.filterList.length, (index) {
              bool isSelected = index == controller.currentFilterIndex.value;
              return InkWell(
                // 改用 InkWell 以获得更好的点击反馈
                onTap: () {
                  debugPrint("🖱点击筛选按钮 $index");
                  controller.changeFilterIndex(index);
                },
                borderRadius: BorderRadius.circular(ScreenAdapter.width(40)),
                child: Container(
                  margin: EdgeInsets.only(right: ScreenAdapter.width(20)),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(32),
                    vertical: ScreenAdapter.height(16),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Color(0xFF3D7CFF) : Colors.white,
                    borderRadius:
                        BorderRadius.circular(ScreenAdapter.width(40)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    controller.filterList[index],
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(38),
                      color:
                          isSelected ? Colors.white : Color(0xFF999999),
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.normal,
                      height: 1.2,
                    ),
                    strutStyle: StrutStyle(
                      fontSize: ScreenAdapter.fontSize(38),
                      height: 1.2,
                      forceStrutHeight: true,
                    ),
                  ),
                ),
              );
            }),
          )),
    );
  }
}
