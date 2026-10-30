#!/data/data/com.termux/files/usr/bin/bash
# 0.2.2 在 Android 上打开会话会抛：flock is not supported on android-arm64
# 成因：node-addon-system/lib/flock.js 的 loadBinding() 平台门只允许 linux|darwin，
#       而 Termux 的 Node 把 process.platform 报成 'android'；上游 optionalDependencies
#       只发 darwin/linux 的 addon，npm 上根本没有 -android-arm64 包（404），
#       所以没有任何 native flock 可用。又因 isLockContention() 只认 EAGAIN/EWOULDBLOCK，
#       ERR_FLOCK_UNSUPPORTED_PLATFORM 一路向上抛，会话根本打不开。
# 处置：android 上让 tryLockExclusive 直接返回（等价于 rc.7 无锁行为）。
#       代价：丢掉跨进程互斥；dsh 在本机是单进程服务，实际不受影响。
# 幂等：已打则跳过。
set -euo pipefail
export PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export PATH=$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=${PREFIX:-/data/data/com.termux/files/usr}/tmp
mkdir -p "$TMPDIR"
export HOME=${TERMUX_HOME:-$(cd "${PREFIX:-/data/data/com.termux/files/usr}/.." && pwd)/home}
F=${1:-$HOME/dsh022/node_modules/@deepseek-ai/node-addon-system/lib/flock.js}
[ -f "$F" ] || { echo "[flock] 未找到 $F"; exit 1; }
cp -n "$F" "$F.rc7bak" && echo "[flock] 已备份 $F.rc7bak"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
MARK = 'dsh android patch'
if MARK in s:
    print('  [skip] 已打过补丁')
    sys.exit(0)
old = "export async function tryLockExclusive(fd) {\n"
new = ("export async function tryLockExclusive(fd) {\n"
       "    // dsh android patch: 无 android 原生 addon，单进程服务下降级为无锁\n"
       "    if (process.platform === 'android')\n        return;\n")
if old not in s:
    print('  [fail] 未找到 tryLockExclusive 签名，可能上游已改结构')
    sys.exit(2)
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print('  已注入: android 无锁降级')
PY
echo '--- 验证 tryLockExclusive ---'
cd "$(dirname "$F")/../../.."
node -e "import('@deepseek-ai/node-addon-system/flock').then(m=>m.tryLockExclusive(1).then(()=>console.log('LOCK_OK')).catch(e=>console.log('ERR',e.code||e.message)))" 2>&1 | tail -2
echo '[flock] 完成。重启 dsh 服务后生效。'
