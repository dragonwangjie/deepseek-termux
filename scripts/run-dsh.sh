#!/data/data/com.termux/files/usr/bin/sh
H=/data/data/com.termux/files/home
U=$H/../usr
export LD_LIBRARY_PATH=$U/lib
export PATH=$U/bin:/system/bin:/system/xbin
export HOME=$H
cd $H/dsh022 || exit 9
[ -f $H/.amd_env ] && . $H/.amd_env
exec $U/bin/node node_modules/@deepseek-ai/dsh/lib/bin.js web --port 3080 --no-open --host 127.0.0.1
