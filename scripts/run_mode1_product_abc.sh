#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL_ROOT="$WORKSPACE_ROOT/dart_prefix_renamer"
SOURCE_PROJECT="${HUANXIN_PROJECT:-/Users/ahs/Documents/work/code/huanxin}"
PRODUCT_ID="${IOS_THIRD_PARTY_PRODUCT_ID:-product_abc}"
OUTPUT_DIR="${MODE1_OUTPUT_DIR:-$WORKSPACE_ROOT/huanxin_mode1_${PRODUCT_ID}_output}"
IPA_DIR="${IPA_OUTPUT_DIR:-$WORKSPACE_ROOT/ipa/$PRODUCT_ID}"
SYMBOL_DIR="${SYMBOL_OUTPUT_DIR:-$WORKSPACE_ROOT/symbols/$PRODUCT_ID}"
IPA_PATH="$IPA_DIR/${PRODUCT_ID}_unsigned.ipa"
RESUME_MODE=false

if [[ "${1:-}" == "--resume" ]]; then
  RESUME_MODE=true
  shift
fi
[[ $# -eq 0 ]] || {
  echo "用法：$0 [--resume]" >&2
  exit 64
}

die() {
  echo "错误：$*" >&2
  exit 1
}

command -v fvm >/dev/null 2>&1 || die "找不到 fvm"
command -v ditto >/dev/null 2>&1 || die "找不到 ditto"
command -v gem >/dev/null 2>&1 || die "找不到 Ruby gem"
[[ -d "$SOURCE_PROJECT" ]] || die "环信源码目录不存在：$SOURCE_PROJECT"
[[ -d "$TOOL_ROOT" ]] || die "工具目录不存在：$TOOL_ROOT"
if "$RESUME_MODE"; then
  [[ -d "$OUTPUT_DIR" ]] || die "--resume 需要已有输出目录：$OUTPUT_DIR"
else
  [[ ! -e "$OUTPUT_DIR" ]] || die "输出目录已存在；如需从第三方 Pod 步骤继续，请传 --resume：$OUTPUT_DIR"
fi

DEPENDENCY_CONFIG="$SOURCE_PROJECT/config/dependencies.yaml"
LIBRARY_POOL_CONFIG="$SOURCE_PROJECT/config/ios_library_pool.yaml"
[[ -f "$DEPENDENCY_CONFIG" ]] || die "缺少依赖配置：$DEPENDENCY_CONFIG"
[[ -f "$LIBRARY_POOL_CONFIG" ]] || die "缺少第三方库池配置：$LIBRARY_POOL_CONFIG"
awk '$1 == "count:" && $2 == "7" { found = 1 } END { exit(found ? 0 : 1) }' \
  "$DEPENDENCY_CONFIG" || die "dependencies.yaml 当前不是 count: 7"

ensure_plist_gem() {
  if ruby -e 'require "plist"' >/dev/null 2>&1; then
    return
  fi
  echo "安装 fluwx 所需的 Ruby plist gem（用户目录）"
  gem install plist --user-install --no-document || die "无法安装 plist gem"
  ruby -e 'require "plist"' >/dev/null 2>&1 || die "plist gem 安装后仍不可用"
}

ensure_plist_gem

TARGETS="lib,packages/aixi_event_logger/lib,packages/aixi_foundation/lib,packages/aixi_design_system/lib,packages/aixi_ui/lib,packages/aixi_network/lib,packages/aixi_platform_bridge/lib,packages/aixi_logging/lib,packages/aixi_media/lib,packages/aixi_audio/lib,packages/aixi_im/lib,packages/aixi_rtc/lib,packages/aixi_gift/lib,packages/aixi_app_config/lib,packages/aixi_feedback/lib"

cd "$TOOL_ROOT"

if ! "$RESUME_MODE"; then
  echo "[1/6] 生成模式一源码副本：$OUTPUT_DIR"
  fvm dart run bin/dart_prefix_renamer.dart \
  --project="$SOURCE_PROJECT" \
  --output="$OUTPUT_DIR" \
  --target="$TARGETS" \
  --prefix="deisoekdi" \
  --assets \
  --rename-directories \
  --reset-metadata \
  --containerize-ios-assets \
  --asset-dir="assets/images" \
  --asset-dir="assets/icons" \
  --container-dir="assets/images" \
  --runtime-config="lib/app_tools/asset_container/asset_container_config.g.dart" \
  --encrypt-dart-strings \
  --string-runtime-config="packages/aixi_app_config/lib/src/string_cipher_config.g.dart" \
  --decrypt-method="decryptedPS" \
  --ios-method-channel-diff \
  --ios-method-channel-include="com.aixi.app/native" \
  --ios-dummy-method-channel-count=12 \
  --ios-method-channel-seed=20260818 \
  --ios-method-channel-entrypoint="lib/main.dart" \
  --ios-custom-pod \
  --ios-custom-pod-id="$PRODUCT_ID" \
  --ios-custom-pod-theme="resource_catalog" \
    --ios-custom-pod-seed=0

  echo "[2/6] 插入 Dart 自动能力"
  fvm dart run bin/dart_prefix_renamer.dart \
  --auto-dart-capabilities \
  --project="$OUTPUT_DIR" \
  --target="lib,packages/aixi_foundation/lib" \
  --dart-differentiation-percent=50 \
    --dart-capability-seed=0
else
  echo "[resume] 保留已有模式一副本和 Dart 自动能力"
fi

echo "[3/6] 接入 7 个 iOS 第三方 SDK Pod"
fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-ios-third-party-sdk-pods \
  --project="$OUTPUT_DIR" \
  --ios-third-party-sdk-product-id="$PRODUCT_ID" \
  --ios-third-party-sdk-dependencies="config/dependencies.yaml" \
  --ios-third-party-sdk-library-pool="config/ios_library_pool.yaml" \
  --ios-third-party-sdk-report-dir="reports/ios-third-party-sdk-pods" \
  --ios-third-party-sdk-seed=0

echo "[4/6] 构建无签名 Release"
cd "$OUTPUT_DIR"
fvm flutter build ios \
  --release \
  --no-codesign \
  --obfuscate \
  --split-debug-info="$SYMBOL_DIR"

echo "[5/6] 打包 unsigned IPA"
IPA_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mode1-ipa.XXXXXX")"
cleanup() {
  rm -rf "$IPA_STAGE"
}
trap cleanup EXIT
mkdir -p "$IPA_STAGE/Payload" "$IPA_DIR"
ditto "$OUTPUT_DIR/build/ios/iphoneos/Runner.app" "$IPA_STAGE/Payload/Runner.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$IPA_STAGE/Payload" \
  "$IPA_PATH"

echo "[6/6] 验证 SDK linkage"
cd "$TOOL_ROOT"
fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-ios-third-party-sdk-pods \
  --verify-ios-third-party-sdk-pods \
  --project="$OUTPUT_DIR" \
  --ios-third-party-sdk-product-id="$PRODUCT_ID" \
  --ios-third-party-sdk-dependencies="config/dependencies.yaml" \
  --ios-third-party-sdk-library-pool="config/ios_library_pool.yaml" \
  --ios-third-party-sdk-report-dir="reports/ios-third-party-sdk-pods" \
  --ios-third-party-sdk-seed=0 \
  --ios-third-party-sdk-release-artifact="$IPA_PATH"

echo
echo "模式一完成：$OUTPUT_DIR"
echo "unsigned IPA：$IPA_PATH"
echo "预期验收：Selected=Declared=Locked=Called=Linked=7"
