#!/bin/zsh
# 生成 Wallpaper Engine 创意工坊预览动图：确定性模拟下按不同预走秒数
# 截连续帧，再由 ffmpeg 合成循环 GIF。帧间隔即模拟间隔，鱼群连贯游动。
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=$(mktemp -d)
QUERY="${1:-daylight=noon&t=2}"   # 例: theme=ink&daylight=dusk&t=2
for t in $(seq 0 11); do
  budget=$((8000 + t * 500))
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1280,800 --virtual-time-budget=$budget \
    --screenshot="$OUT/frame-$(printf %02d $t).png" \
    "file://$PWD/index.html?$QUERY" >/dev/null 2>&1
done
ffmpeg -y -loglevel error -framerate 5 -i "$OUT/frame-%02d.png" \
  -vf "fps=5,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
  preview.gif
rm -rf "$OUT"
echo "已生成 $(pwd)/preview.gif"
