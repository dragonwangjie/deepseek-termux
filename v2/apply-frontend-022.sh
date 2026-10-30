#!/data/data/com.termux/files/usr/bin/bash
# 把移动端适配注入 0.2.2 的 Termux 安装（rc.7 时代脚本默认路径指错）。
# 缺口成因：早期 apply-frontend.sh 跑在 proot 副本上，Termux 真 dist 里 dsh-mobile-adapt=0。
set -euo pipefail
export PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export PATH=$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=${PREFIX:-/data/data/com.termux/files/usr}/tmp
mkdir -p "$TMPDIR"
export HOME=${TERMUX_HOME:-$(cd "${PREFIX:-/data/data/com.termux/files/usr}/.." && pwd)/home}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HTML=${1:-$HOME/dsh022/node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html}
[ -f "$HTML" ] || { echo "[fe] 未找到 $HTML"; exit 1; }
bash "$ROOT/apply-frontend.sh" "$HTML"
echo '--- 校验 ---'
for m in dsh-mobile-adapt 'AbortSignal.any' viewport-fit; do
  printf '%-18s %s\n' "$m" "$(grep -c "$m" "$HTML")"
done
echo '0.2.2 上游 manifest 已是 display: standalone，无需改。重启服务生效。'
