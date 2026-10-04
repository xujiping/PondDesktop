#!/bin/zsh
# 一池网页壁纸 · Mac 端测试套件。
#
#   ./tools/test.sh                 # 语法 + 自检 + drive 交互场景 + soak 长跑 + 截图矩阵
#   ./tools/test.sh --save-baseline # 同上，并把截图矩阵存为金基准（首次或有意变更后）
#
# 截图矩阵与基准逐张算 PSNR：确定性渲染下应完全一致（inf）；
# Chrome 升级可能轻微改变光栅化，低于阈值时重存基准即可。
set -uo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASELINE_DIR="tools/baselines"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILURES=0

say()  { printf '\033[1m== %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

expect_title() {  # expect_title <url> <virtual-ms> <前缀>
  local dom
  dom=$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=$2 --dump-dom "$1" 2>/dev/null)
  if grep -q "<title>$3" <<< "$dom"; then ok "$3"; else bad "$(grep -o '<title>[^<]*' <<< "$dom" | head -1 | cut -c8-) （期望 $3）"; fi
}

say '语法检查'
for f in js/*.js; do
  if node --check "$f" 2>/dev/null; then ok "$f"; else bad "$f 语法错误"; fi
done
python3 -c 'import json; json.load(open("project.json"))' && ok 'project.json 合法' || bad 'project.json 解析失败'

say '功能自检（?selftest=1）'
expect_title "file://$PWD/index.html?selftest=1" 2500 'SELFTEST-PASS'

say 'WE 协议交互场景（?drive=1）'
expect_title "file://$PWD/index.html?drive=1&t=2" 4000 'DRIVE-PASS'

say '长跑浸泡（?soak=1800，快进 30 分钟）'
expect_title "file://$PWD/index.html?soak=1800" 2500 'SOAK-PASS'

say '自动时段对表（?clock=23 应入夜）'
expect_title "file://$PWD/index.html?clock=23&selftest=1" 2500 'SELFTEST-PASS'

# name|query|width|height|额外 Chrome 参数
MATRIX=(
  'default|daylight=noon&t=2&freeze=1|1920|1080|'
  'night|daylight=night&t=2&freeze=1|1920|1080|'
  'ink-dusk|theme=ink&daylight=dusk&t=2&freeze=1|2560|1440|'
  'ultrawide|daylight=noon&t=2&freeze=1|3440|1440|'
  'retina|daylight=noon&t=2&freeze=1|1440|900|--force-device-scale-factor=2'
  'dense|density=1.8&fish=48&daylight=noon&t=2&freeze=1|1920|1080|'
)

if [[ "${1:-}" == "--save-baseline" ]]; then
  say '保存金基准截图'
  mkdir -p "$BASELINE_DIR"
  for row in "${MATRIX[@]}"; do
    IFS='|' read -r name query w h extra <<< "$row"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=${w},${h} ${=extra} \
      --virtual-time-budget=800 --screenshot="$BASELINE_DIR/$name.png" \
      "file://$PWD/index.html?$query" >/dev/null 2>&1
    [[ -s "$BASELINE_DIR/$name.png" ]] && ok "$name.png" || bad "$name.png 截图失败"
  done
  echo "基准已保存到 $BASELINE_DIR（$FAILURES 个失败）"
  exit $FAILURES
fi

say '截图矩阵 vs 金基准（PSNR，确定性渲染应为 inf）'
if [[ ! -d "$BASELINE_DIR" ]]; then
  echo '  尚无基准。先运行: ./tools/test.sh --save-baseline'
else
  for row in "${MATRIX[@]}"; do
    IFS='|' read -r name query w h extra <<< "$row"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=${w},${h} ${=extra} \
      --virtual-time-budget=800 --screenshot="$TMP/$name.png" \
      "file://$PWD/index.html?$query" >/dev/null 2>&1
    if [[ ! -s "$TMP/$name.png" ]]; then bad "$name 截图失败"; continue; fi
    if [[ ! -s "$BASELINE_DIR/$name.png" ]]; then bad "$name 无基准"; continue; fi
    psnr=$(ffmpeg -i "$TMP/$name.png" -i "$BASELINE_DIR/$name.png" -filter_complex psnr -f null - 2>&1 | grep -o 'average:[0-9a-z.]*' | cut -d: -f2)
    if [[ "$psnr" == "inf" ]] || (( $(echo "$psnr > 40" | bc -l 2>/dev/null || echo 0) )); then
      ok "$name PSNR=${psnr}dB"
    else
      bad "$name PSNR=${psnr}dB（回归或需重存基准）"
    fi
  done
fi

echo ''
if (( FAILURES == 0 )); then printf '\033[32m全部通过 ✅\033[0m\n'; else printf '\033[31m%d 项失败 ❌\033[0m\n' $FAILURES; fi
exit $FAILURES
