#!/data/data/com.termux/files/usr/bin/sh
H=/data/data/com.termux/files/home
export PATH=$H/../usr/bin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=$H/../usr/lib
export HOME=$H
termux-wake-lock 2>/dev/null
cd $H/dsh022 || exit 1
[ -f $H/.amd_env ] && . $H/.amd_env
BIN=$H/../usr/bin/node
A=node_modules/@deepseek-ai/dsh/lib/bin.js
refresh_url() {
  grep http $H/dsh_web.log | tail -1 | sed "s/^dsh web: //" | tr -d "\"'" > $H/dsh_url.txt
}
while :; do
  if ! pgrep -f 'dsh/lib/bin.js' >/dev/null 2>&1; then
    setsid $BIN $A web --port 3080 --no-open --host 127.0.0.1 >> $H/dsh_web.log 2>&1 </dev/null &
    echo "spawn $(date +%T) pid=$!" >> $H/supervise.log
    sleep 15
  fi
  refresh_url
  sleep 20
done
