import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/models/address_model.dart';
import '../data/models/api_response.dart';
import '../data/repositories/exam_repository.dart';
import '../services/screenAdapter.dart';

/// 省市区三级联动选择器(底部弹层)
///
/// 用法:
/// ```dart
/// final result = await AreaPicker.show(initial: currentSelection);
/// if (result != null) { /* 使用 result */ }
/// ```
/// 返回 [AreaSelection]?;用户关闭/取消返回 null。
class AreaPicker {
  /// 弹出选择器
  static Future<AreaSelection?> show({AreaSelection? initial}) {
    return Get.bottomSheet(
      _AreaPickerSheet(initial: initial),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
    );
  }

  /// 省市区全国数据稳定,会话内静态缓存复用,避免重复请求
  static List<AreaOption>? _provinceCache;
  static final Map<int, List<AreaOption>> _cityCache = {};
  static final Map<int, List<AreaOption>> _districtCache = {};
}

class _AreaPickerSheet extends StatefulWidget {
  final AreaSelection? initial;

  const _AreaPickerSheet({this.initial});

  @override
  State<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<_AreaPickerSheet> {
  /// 0=省份 1=城市 2=区县
  int _level = 0;

  List<AreaOption> _provinceList = [];
  List<AreaOption> _cityList = [];
  List<AreaOption> _districtList = [];

  AreaOption? _province;
  AreaOption? _city;
  AreaOption? _district;

  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  /// 拉取省份列表(带缓存)
  Future<void> _loadProvinces() async {
    if (AreaPicker._provinceCache != null) {
      _provinceList = AreaPicker._provinceCache!;
      _restoreInitial();
      return;
    }
    await _fetchList(
      () => ExamRepository.to.getAreaList(),
      onSuccess: (list) {
        AreaPicker._provinceCache = list;
        _provinceList = list;
        _restoreInitial();
      },
    );
  }

  /// 拉取城市列表(带缓存)
  Future<void> _loadCities(int provinceId) async {
    final cached = AreaPicker._cityCache[provinceId];
    if (cached != null) {
      _cityList = cached;
      return;
    }
    await _fetchList(
      () => ExamRepository.to.getAreaList(province: provinceId),
      onSuccess: (list) {
        AreaPicker._cityCache[provinceId] = list;
        _cityList = list;
      },
    );
  }

  /// 拉取区县列表(带缓存)
  Future<void> _loadDistricts(int cityId) async {
    final cached = AreaPicker._districtCache[cityId];
    if (cached != null) {
      _districtList = cached;
      return;
    }
    await _fetchList(
      () => ExamRepository.to.getAreaList(city: cityId),
      onSuccess: (list) {
        AreaPicker._districtCache[cityId] = list;
        _districtList = list;
      },
    );
  }

  Future<void> _fetchList(
    Future<ApiResponse<List<AreaOption>>> Function() request, {
    required void Function(List<AreaOption>) onSuccess,
  }) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await request();
      final data = response.data;
      if (response.isSuccess && data != null) {
        onSuccess(data);
      } else {
        _error = response.message.isNotEmpty ? response.message : '获取地区失败';
      }
    } catch (e) {
      _error = '获取地区失败，请重试';
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// 编辑回填:按初始省市区逐级定位并恢复选择
  void _restoreInitial() {
    final initial = widget.initial;
    if (initial == null || _provinceList.isEmpty) return;
    final province = _findOption(_provinceList, initial.provinceId);
    if (province == null) return;

    _province = province;
    _loadCities(province.value).then((_) {
      if (!mounted) return;
      final city = _findOption(_cityList, initial.cityId);
      if (city == null) {
        setState(() => _level = 1);
        return;
      }
      _city = city;
      if (initial.districtId == null) {
        setState(() => _level = 1);
        return;
      }
      _loadDistricts(city.value).then((_) {
        if (!mounted) return;
        final district = _findOption(_districtList, initial.districtId!);
        if (district == null) return;
        setState(() {
          _district = district;
          _level = 2;
        });
      });
    });
  }

  AreaOption? _findOption(List<AreaOption> list, int value) {
    for (final item in list) {
      if (item.value == value) return item;
    }
    return null;
  }

  /// 选中列表项后自动进入下一级
  void _onSelect(AreaOption option) {
    setState(() {
      switch (_level) {
        case 0:
          _province = option;
          _city = null;
          _district = null;
          _cityList = [];
          _districtList = [];
          _level = 1;
          _loadCities(option.value);
          break;
        case 1:
          _city = option;
          _district = null;
          _districtList = [];
          _level = 2;
          _loadDistricts(option.value);
          break;
        case 2:
          _district = option;
          break;
      }
    });
  }

  /// 切换 Tab(前置层级未选择时不可进入)
  void _switchLevel(int level) {
    if (level == 0) {
      setState(() => _level = 0);
      return;
    }
    if (level == 1 && _province != null) {
      if (_cityList.isEmpty && _city == null) {
        _loadCities(_province!.value);
      }
      setState(() => _level = 1);
      return;
    }
    if (level == 2 && _city != null) {
      if (_districtList.isEmpty && _district == null) {
        _loadDistricts(_city!.value);
      }
      setState(() => _level = 2);
    }
  }

  void _confirm() {
    final province = _province;
    final city = _city;
    if (province == null || city == null) return;
    Get.back(result: AreaSelection(
      provinceId: province.value,
      provinceName: province.name,
      cityId: city.value,
      cityName: city.name,
      districtId: _district?.value,
      districtName: _district?.name ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: Get.height * 0.75),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(ScreenAdapter.radius(32))),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动条
            Container(
              width: ScreenAdapter.width(120),
              height: ScreenAdapter.height(8),
              margin: EdgeInsets.only(
                top: ScreenAdapter.height(24),
                bottom: ScreenAdapter.height(20),
              ),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(ScreenAdapter.radius(4)),
              ),
            ),
            // 标题 + 关闭
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(width: ScreenAdapter.width(48)),
                Text(
                  '选择地区',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(46),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF333333),
                  ),
                ),
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: ScreenAdapter.width(24)),
                    child: Icon(
                      Icons.close,
                      color: const Color(0xFF333333),
                      size: ScreenAdapter.width(56),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: ScreenAdapter.height(24)),
            // 三级 Tab
            Padding(
              padding: EdgeInsets.symmetric(horizontal: ScreenAdapter.width(32)),
              child: Row(
                children: List.generate(3, (index) {
                  final selected = _level == index;
                  final String text;
                  switch (index) {
                    case 0:
                      text = _province?.name ?? '请选择省份';
                      break;
                    case 1:
                      text = _city?.name ?? '请选择城市';
                      break;
                    default:
                      text = _district?.name ?? '请选择区县';
                  }
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _switchLevel(index),
                      child: Container(
                        margin: EdgeInsets.only(right: ScreenAdapter.width(16)),
                        padding: EdgeInsets.symmetric(
                          horizontal: ScreenAdapter.width(16),
                          vertical: ScreenAdapter.height(16),
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF3D7CFF)
                              : const Color(0xFFF5F6F8),
                          borderRadius:
                              BorderRadius.circular(ScreenAdapter.radius(12)),
                        ),
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(28),
                            color: selected
                                ? Colors.white
                                : (index <= _level ? const Color(0xFF333333) : const Color(0xFFB1B8CA)),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            SizedBox(height: ScreenAdapter.height(24)),
            // 列表 / 加载中 / 错误
            SizedBox(
              height: ScreenAdapter.height(560),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                      ? _buildError()
                      : _buildList(),
            ),
            // 确认按钮
            Padding(
              padding: EdgeInsets.fromLTRB(
                ScreenAdapter.width(32),
                ScreenAdapter.height(16),
                ScreenAdapter.width(32),
                ScreenAdapter.height(24),
              ),
              child: SizedBox(
                width: double.infinity,
                height: ScreenAdapter.height(110),
                child: ElevatedButton(
                  onPressed:
                      (_province != null && _city != null) ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D7CFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCCCCCC),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          ScreenAdapter.radius(20)),
                    ),
                  ),
                  child: Text(
                    '确定',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(44),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(30),
              color: const Color(0xFF999999),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(24)),
          TextButton(
            onPressed: () {
              switch (_level) {
                case 0:
                  _loadProvinces();
                  break;
                case 1:
                  _loadCities(_province!.value);
                  break;
                default:
                  _loadDistricts(_city!.value);
              }
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final list = switch (_level) {
      0 => _provinceList,
      1 => _cityList,
      _ => _districtList,
    };
    final selected = switch (_level) {
      0 => _province,
      1 => _city,
      _ => _district,
    };
    if (list.isEmpty) {
      return Center(
        child: Text(
          _level == 0 ? '暂无省份数据' : '暂无数据',
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(30),
            color: const Color(0xFF999999),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: ScreenAdapter.width(32),
        endIndent: ScreenAdapter.width(32),
        color: const Color(0xFFF5F5F5),
      ),
      itemBuilder: (context, index) {
        final option = list[index];
        final isSelected = selected?.value == option.value;
        return GestureDetector(
          onTap: () => _onSelect(option),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(48),
              vertical: ScreenAdapter.height(28),
            ),
            color: isSelected
                ? const Color(0xFFF0F7FF)
                : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.name,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(32),
                      color: isSelected
                          ? const Color(0xFF3D7CFF)
                          : const Color(0xFF333333),
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color: const Color(0xFF3D7CFF),
                    size: ScreenAdapter.width(40),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
