/// 版本检测数据模型
class VersionModel {
  /// 是否需要更新
  final bool needUpdate;

  /// 新版本号
  final String? newVersion;

  /// 旧版本号（当前版本）
  final String? oldVersion;

  /// 包大小
  final String? packageSize;

  /// 升级内容
  final String? content;

  /// 下载地址（Android APK）
  final String? downloadUrl;

  /// iOS App Store 地址
  final String? iosUrl;

  /// 鸿蒙华为应用市场地址
  final String? ohosUrl;

  /// 是否强制更新 (1=强制, 0=非强制)
  final bool enforce;

  VersionModel({
    this.needUpdate = false,
    this.newVersion,
    this.oldVersion,
    this.packageSize,
    this.content,
    this.downloadUrl,
    this.iosUrl,
    this.ohosUrl,
    this.enforce = false,
  });

  factory VersionModel.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return VersionModel();
    }

    // 后端 Version::check 返回的数据结构：
    // 有更新时返回版本信息，无更新时可能返回空或特定标记
    final bool needUpdate = json.isNotEmpty &&
        (json['newversion'] != null ||
            json['new_version'] != null ||
            json['need_update'] == true ||
            json['need_update'] == 1);

    return VersionModel(
      needUpdate: needUpdate,
      newVersion:
          json['newversion']?.toString() ?? json['new_version']?.toString(),
      oldVersion: json['oldversion']?.toString() ??
          json['old_version']?.toString() ??
          json['version']?.toString(),
      packageSize:
          json['packagesize']?.toString() ?? json['package_size']?.toString(),
      content: json['content']?.toString() ?? json['upgradetext']?.toString(),
      downloadUrl: json['downloadurl']?.toString() ??
          json['download_url']?.toString() ??
          json['androidurl']?.toString(),
      iosUrl: json['iosurl']?.toString() ?? json['ios_url']?.toString(),
      ohosUrl: json['ohosurl']?.toString() ?? json['ohos_url']?.toString(),
      enforce: json['enforce'] == 1 ||
          json['enforce'] == true ||
          json['enforce'] == '1',
    );
  }

  Map<String, dynamic> toJson() => {
        'need_update': needUpdate,
        'newversion': newVersion,
        'oldversion': oldVersion,
        'packagesize': packageSize,
        'content': content,
        'downloadurl': downloadUrl,
        'iosurl': iosUrl,
        'ohosurl': ohosUrl,
        'enforce': enforce ? 1 : 0,
      };
}
