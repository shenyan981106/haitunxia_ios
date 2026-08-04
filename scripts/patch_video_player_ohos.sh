#!/bin/bash
# 修复 video_player_ohos 在鸿蒙 SDK 5.1.0(18) 上的编译错误
# 该脚本会自动将修复后的 VideoPlayer.ets 复制到 PubCache 中
# 使用方法：在执行 flutter build hap 之前运行此脚本
#   cd scripts && bash patch_video_player_ohos.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_FILE="VideoPlayer.ets"
TARGET_RELATIVE_PATH="ohos/src/main/ets/components/videoplayer/$TARGET_FILE"
SOURCE_FILE="$PROJECT_ROOT/third_party/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayer.ets"

# 1. 查找 Flutter PubCache 路径
PUB_CACHE_PATH=""
# 尝试通过 flutter 命令获取
if command -v flutter &> /dev/null; then
    PUB_CACHE_PATH=$(flutter pub cache path 2>/dev/null | tr -d '[:space:]')
fi

# 如果失败或为空，尝试默认路径
if [ -z "$PUB_CACHE_PATH" ] || [ ! -d "$PUB_CACHE_PATH" ]; then
    # macOS 默认路径
    if [ -d "$HOME/.pub-cache" ]; then
        PUB_CACHE_PATH="$HOME/.pub-cache"
    # Linux 默认路径
    elif [ -d "$HOME/.pub-cache" ]; then
        PUB_CACHE_PATH="$HOME/.pub-cache"
    # 使用 Dart 环境变量
    elif [ -n "$PUB_CACHE" ] && [ -d "$PUB_CACHE" ]; then
        PUB_CACHE_PATH="$PUB_CACHE"
    else
        echo "❌ 无法找到 PubCache 路径。请确保 Flutter 已正确安装。"
        exit 1
    fi
fi

echo "PubCache 路径: $PUB_CACHE_PATH"

# 2. 检查源文件
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ 找不到源文件: $SOURCE_FILE"
    echo "请确保已从 Git 仓库克隆了 video_player_ohos 的修复版本到 third_party 目录。"
    exit 1
fi

echo "源文件: $SOURCE_FILE"

# 3. 在 PubCache 中查找 video_player_ohos
GIT_CACHE_PATH="$PUB_CACHE_PATH/git"
if [ ! -d "$GIT_CACHE_PATH" ]; then
    echo "未找到 git 缓存目录，可能尚未使用 git 依赖。"
    exit 0
fi

echo "正在搜索 video_player_ohos 实例..."

# 遍历 git 缓存查找 video_player_ohos
FOUND_DIRS=$(find "$GIT_CACHE_PATH" -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
    if [ -f "$dir/$TARGET_RELATIVE_PATH" ] && [ -f "$dir/pubspec.yaml" ]; then
        if grep -q "name: video_player_ohos" "$dir/pubspec.yaml" 2>/dev/null; then
            echo "$dir"
        fi
    fi
done)

if [ -z "$FOUND_DIRS" ]; then
    echo "未在 PubCache 中找到 video_player_ohos。"
    echo "请先运行 'flutter pub get' 下载依赖。"
    exit 0
fi

# 显示找到的路径
echo "$FOUND_DIRS" | while read -r dir; do
    echo "找到 video_player_ohos: $dir"
done

# 4. 复制修复后的文件
echo ""
echo "正在应用修复..."
echo "$FOUND_DIRS" | while read -r TARGET_DIR; do
    DEST_FILE="$TARGET_DIR/$TARGET_RELATIVE_PATH"
    echo "正在复制修复文件到: $DEST_FILE"
    cp -f "$SOURCE_FILE" "$DEST_FILE"
    
    if [ -f "$DEST_FILE" ]; then
        echo "✅ 修复成功: $DEST_FILE"
    else
        echo "❌ 复制失败: $DEST_FILE"
        exit 1
    fi
done

echo ""
echo "所有 video_player_ohos 实例已修补完成。"
echo "现在可以运行 flutter build hap 进行鸿蒙应用打包。"
