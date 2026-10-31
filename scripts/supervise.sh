#!/data/data/com.termux/files/usr/bin/sh
H=/data/data/com.termux/files/home
U=$H/../usr
export PATH=$U/bin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=$U/lib
export HOME=$H
termux-wake-lock 2>/dev/null
cd $H/dsh022 || exit 1
[ -f $H/.amd_env ] && . $H/.amd_env
BIN=$U/bin/node
A=node_modules/@deepseek-ai/dsh/lib/bin.js
L=$H/dsh_web.log
is_up() {
  if [ -n "$OLDPID" ]; then kill -0 $OLDPID 2>/dev/null || return 1; fi
  $U/bin/curl -s -m 5 -o /dev/null http://127.0.0.1:3080/ && return 0
  return 1
}
refresh_url() { grep http $L | tail -1 | sed "s/^dsh web: //" | tr -d "\"'" > $H/dsh_url.txt; }
while :; do
  if ! is_up; then
    pkill -9 -f 'dsh/lib/bin.js' 2>/dev/null
    sleep 2
    OLDPID=""
    setsid $BIN $A web --port 3080 --no-open --host 127.0.0.1 >> $L 2>&1 </dev/null &
    SP=$!
    echo "spawn $(date +%T) pid=$SP" >> $H/supervise.log
    n=0
    while [ $n -lt 6 ]; do
      sleep 5
      if $U/bin/curl -s -m 5 -o /dev/null http://127.0.0.1:3080/; then break; fi
      n=$((n+1))
    done
    echo "probe $(date +%T) n=$n" >> $H/supervise.log
    OLDPID=$SP
  fi
  refresh_url
  sleep 20
done
