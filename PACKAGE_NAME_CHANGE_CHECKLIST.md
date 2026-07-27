# 包名更改清单

## 目标包名
`com.zgjan.haitunxia`

---

## 1. Android 平台



**说明**：`applicationId`（用于 app 备案）与 Kotlin 代码包名可以分离，代码包名 `com.zgjan.xmshop` 无需修改。

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| android/app/build.gradle.kts (L18) | `namespace = "com.zgjan.haitunxia"` | 不变 | ✓ |
| android/app/build.gradle.kts (L35) | `applicationId = "com.zgjan.haitunxia"` | 不变 | ✓ |
| android/app/src/main/AndroidManifest.xml (L9) | `android:name="com.zgjan.xmshop.MainActivity"` | 不变（代码包名） | ✓ |
| android/app/src/main/kotlin/com/zgjan/xmshop/MainActivity.kt (L1) | `package com.zgjan.xmshop` | 不变（代码包名） | ✓ |

---

## 2. iOS 平台

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| ios/Runner.xcodeproj/project.pbxproj (L371) | `PRODUCT_BUNDLE_IDENTIFIER = com.zgjan.haitunxia` | 不变 | ✓ |
| ios/Runner.xcodeproj/project.pbxproj (L551, L573) | `PRODUCT_BUNDLE_IDENTIFIER = com.zgjan.haitunxia` | 不变 | ✓ |

---

## 3. macOS 平台

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| macos/Runner/Configs/AppInfo.xcconfig (L11) | `PRODUCT_BUNDLE_IDENTIFIER = com.example.xmshop` | `com.zgjan.haitunxia` | ✗ |
| macos/Runner.xcodeproj/project.pbxproj (L388, L402, L416) | `PRODUCT_BUNDLE_IDENTIFIER = com.example.xmshop.RunnerTests` | `com.zgjan.haitunxia.RunnerTests` | ✗ |

---

## 4. Linux 平台

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| linux/CMakeLists.txt (L10) | `APPLICATION_ID "com.example.xmshop"` | `"com.zgjan.haitunxia"` | ✗ |

---

## 5. 鸿蒙平台

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| ohos/AppScope/app.json5 (L3) | `"bundleName": "com.zgjan.haitunxia"` | 不变 | ✓ |

---

## 6. Flutter 配置

| 文件路径 | 当前值 | 目标值 | 状态 |
|---------|--------|--------|------|
| pubspec.yaml (L114) | `url_scheme: com.zgjan.haitunxia` | 不变 | ✓ |

---

## 需要立即处理的关键项（按优先级）

1. **macOS AppInfo.xcconfig** - 主应用的 Bundle ID
2. **macOS project.pbxproj** - RunnerTests 的 Bundle ID
3. **Linux CMakeLists.txt** - 应用标识符

---

## 操作步骤建议

```bash
# 1. 更新 macOS AppInfo.xcconfig
# 编辑 macos/Runner/Configs/AppInfo.xcconfig
# 将 "com.example.xmshop" 改为 "com.zgjan.haitunxia"

# 2. 更新 macOS project.pbxproj 中的 RunnerTests Bundle ID
# 将所有 "com.example.xmshop.RunnerTests" 改为 "com.zgjan.haitunxia.RunnerTests"

# 3. 更新 Linux CMakeLists.txt
# 将 "com.example.xmshop" 改为 "com.zgjan.haitunxia"
```
