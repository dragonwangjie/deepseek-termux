#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# node-addon-require-builtin (narb) Android 本地构建
# -----------------------------------------------------------------------------
# 背景：dsh 0.2.x 硬依赖 narb，官方只发 darwin/linux-gnu/linux-musl/win32，
#       无 android 预编译 -> dsh web 启动即 fatal：
#       "No usable native binding found for node-addon-require-builtin-android-arm64"
#
# 已实测做法（2026-10-29，真机 Termux + dsh 0.2.2-alpha.2 跑通）：
#   1. clone 上游源码（版本对齐已装 narb）
#   2. 只改 scripts/build.ts 平台白名单：linux -> linux|android（2 处）
#      不再需要 issue #6 说的 platform.cc bionic 分支：上游已改为
#      #elif defined(__linux__) && defined(__aarch64__)，不再判 __GLIBC__
#   3. npm 装依赖（删 packageManager 绕开 pnpm），再单独装 esbuild 给 tsx 用
#   4. tsx 跑 build.ts，napi backend；产物落在 napi-v9-linux-arm64-musl/
#      （build.ts 把 bionic 归为 musl，不是 bug）
#   5. 拷到 loader 实际寻址位置 build/napi/napi-v9-android-arm64/
#   6. 自检 bindingSource=local-build 且 requireBuiltin 可用
#
# 用法：bash setup-narb-android.sh [--root <@deepseek-ai 目录>] [--rebuild]
# 幂等：自检通过则直接退出 0。
# =============================================================================
set -uo pipefail
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[v]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m[x]\033[0m %s\n' "$*"; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin"
export LD_LIBRARY_PATH="$PREFIX/lib"
export TMPDIR="${TMPDIR:-$HOME/.tmp}"; mkdir -p "$TMPDIR"

SCOPE=""; REBUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) SCOPE="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    *) bad "未知参数: $1"; exit 64 ;;
  esac
done
if [ -z "$SCOPE" ]; then
  for c in "$PREFIX/lib/node_modules/@deepseek-ai" "$HOME/dsh022/node_modules/@deepseek-ai"; do
    [ -d "$c" ] && { SCOPE="$c"; break; }
  done
fi
[ -n "$SCOPE" ] || { bad "未找到 @deepseek-ai，用 --root 指定"; exit 1; }

# --- 向上查找顶层 node_modules 里的 narb（常见提升位置）---------------------
NARB=""; INSTALL_ROOT=""
d="$SCOPE"
while [ "$d" != "/" ] && [ -n "$d" ]; do
  for cand in "$d/node_modules/node-addon-require-builtin" "$d/node-addon-require-builtin"; do
    if [ -d "$cand" ]; then NARB="$cand"; INSTALL_ROOT="$d"; break 2; fi
  done
  d="$(dirname "$d")"
done
if [ -z "$NARB" ]; then ok "此 dsh 不依赖 narb，无需处理"; exit 0; fi
NARB_VER="$(node -p "require('$NARB/package.json').version" 2>/dev/null)"
DEST="$NARB/build/napi/napi-v9-android-arm64"
info "narb: $NARB (v${NARB_VER:-?})"

verify() {
  ( cd "$INSTALL_ROOT" && node -e '
    try {
      const n = require("node-addon-require-builtin");
      const i = n.getBindingInfo();
      if (i.bindingSource !== "local-build") { console.log("bindingSource=" + i.bindingSource); process.exit(1); }
      const m = n.requireBuiltin("internal/modules/esm/loader");
      if (typeof m.getOrInitializeCascadedLoader !== "function") { console.log("api_missing"); process.exit(1); }
      console.log("bindingSource=" + i.bindingSource + " abi=" + i.abi);
    } catch (e) { console.log(String(e.message).split("\n")[0]); process.exit(1); }
  ' 2>&1 )
}

if [ "$REBUILD" != 1 ]; then
  V=$(verify)
  if [ $? = 0 ]; then ok "narb 已可用（$V），跳过构建（--rebuild 可强制）"; exit 0; fi
  warn "当前不可用：$V"
fi

# --- 1/5 源码 --------------------------------------------------------------
SRC="${NARB_SRC:-$HOME/.cache/narb-src-${NARB_VER:-unknown}}"
info "1/5 源码 $SRC"
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"; rm -rf "$SRC"
  timeout 300 git clone --depth 1 https://github.com/deepseek-ai/dsh-node-addon-require-builtin.git "$SRC" >/dev/null 2>&1 \
    || { bad "git clone 失败（网络？）"; exit 1; }
fi
SRC_VER="$(node -p "require('$SRC/package.json').version" 2>/dev/null)"
[ -n "${NARB_VER:-}" ] && [ -n "${SRC_VER:-}" ] && [ "$SRC_VER" != "$NARB_VER" ] \
  && warn "源码 v$SRC_VER != 已装 v$NARB_VER，ABI 可能不符"

# --- 2/5 平台白名达 --------------------------------------------------------
info "2/5 build.ts 平台补丁"
BT="$SRC/scripts/build.ts"
[ -f "$BT" ] || { bad "缺少 $BT（上游布局变动）"; exit 1; }
if grep -q "process.platform === 'android'" "$BT"; then
  ok "  已打过"
else
  cp "$BT" "$BT.orig"
  sed -i "s/=== 'linux') {/=== 'linux' || process.platform === 'android') {/g" "$BT"
  HITS=$(grep -c "process.platform === 'android'" "$BT")
  if [ "$HITS" = 0 ]; then
    bad "  锚点未命中，已回退（上游改了 compileArgs）"
    cp "$BT.orig" "$BT"; grep -n "unsupported platform" "$BT" | head -2; exit 2
  fi
  ok "  已改 $HITS 处"
fi

# --- 3/5 依赖 --------------------------------------------------------------
info "3/5 构建依赖（pnpm 无 android 产物，用 npm）"
cd "$SRC" || exit 1
sed -i '/"packageManager"/d' package.json
if [ ! -f node_modules/tsx/dist/cli.mjs ]; then
  timeout 900 npm install --no-audit --no-fund --ignore-scripts --loglevel=error >/dev/null 2>&1
fi
if [ ! -d node_modules/@esbuild/android-arm64 ] && [ ! -d node_modules/@esbuild/linux-arm64 ]; then
  timeout 600 npm install esbuild@latest --no-audit --no-fund --loglevel=error >/dev/null 2>&1
fi
[ -f node_modules/tsx/dist/cli.mjs ] || { bad "tsx 缺失，无法编译"; exit 1; }
ok "  tsx + esbuild 就位"

# --- 4/5 编译 --------------------------------------------------------------
info "4/5 编译 napi-v9 addon（C++，估 3-15 分）"
export NARB_BACKEND=napi NARB_PRODUCT=require-builtin NARB_BUILD_OUTPUT=build
timeout 1500 node node_modules/tsx/dist/cli.mjs scripts/build.ts 2>&1 | tail -4
BUILT=$(find "$SRC/packages" -name 'require_builtin.node' 2>/dev/null | head -1)
[ -n "$BUILT" ] || { bad "未产出 .node"; exit 1; }
ok "  $BUILT"

# --- 5/5 归位 + 自检 ------------------------------------------------------
info "5/5 装到 loader 寻址路径（build.ts 把 bionic 归为 musl，需重命名）"
mkdir -p "$DEST" || exit 1
cp "$BUILT" "$DEST/require_builtin.node" || { bad "拷贝失败"; exit 1; }
chmod 644 "$DEST/require_builtin.node" 2>/dev/null
V=$(verify)
if [ $? != 0 ]; then bad "自检未通过：$V"; bad "检查 $DEST 与 node 版本是否匹配"; exit 1; fi
ok "自检通过：$V"
info "完成。重启 dsh：dsh web"
