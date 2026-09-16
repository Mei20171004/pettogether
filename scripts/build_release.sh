#!/usr/bin/env bash
# 打一个可以上传 App Store 的正式包。
# 用法：在项目根目录执行  ./scripts/build_release.sh
set -uo pipefail
cd "$(dirname "$0")/.."

KEY_FILE="revenuecat.json"

if [ ! -f "$KEY_FILE" ]; then
  echo "✗ 找不到 $KEY_FILE。请照着 revenuecat.example.json 建一个，并填入 RevenueCat 的 appl_ Key。"
  exit 1
fi

if ! grep -q '"appl_' "$KEY_FILE"; then
  echo "✗ $KEY_FILE 里还没有填入真正的 Key。"
  echo "  请打开这个文件，把占位文字换成 RevenueCat 里以 appl_ 开头的那串，然后再运行一次。"
  exit 1
fi

# 清掉上一次的产物，否则下面的检查可能看到旧文件而误判。
rm -rf build/ios/archive build/ios/ipa

echo "→ 正在打包，大约需要一分钟…"
if ! flutter build ipa --dart-define-from-file="$KEY_FILE"; then
  echo "✗ 打包失败，请把上面的错误信息发给开发。"
  exit 1
fi

# 确认 Key 真的被编进了这个包，而不是只写在命令里。
APP=$(find build/ios/archive -type f \
        -path "*Runner.app/Frameworks/App.framework/App" 2>/dev/null | head -1)
# 用 grep -c 而不是 grep -q：-q 匹配到就提前关闭管道，会让上游的
# strings 被信号终止，在 pipefail 下整条管道会被误判为失败。
FOUND=0
if [ -n "$APP" ]; then
  FOUND=$(strings -a "$APP" | grep -c '^appl_' || true)
fi

if [ "$FOUND" -gt 0 ]; then
  echo
  echo "✓ 完成。正式包已经带上 RevenueCat 的 Key。"
  echo "  文件在：build/ios/ipa/"
else
  echo
  echo "✗ 包里没有找到 Key，请不要上传这个包，把这段信息发给开发。"
  exit 1
fi
