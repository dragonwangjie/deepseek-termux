export PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export HOME=/data/data/com.termux/files/home
[ -f /data/data/com.termux/files/home/.amd_env ] && . /data/data/com.termux/files/home/.amd_env
echo "amd_key_set=${AMD_RADEON_KEY:+yes}"
cd $HOME/dsh022 || exit 1
pkill -f 'dsh/lib/bin.js' 2>/dev/null
sleep 2
nohup /data/data/com.termux/files/usr/bin/node node_modules/@deepseek-ai/dsh/lib/bin.js web --port 3080 --host 127.0.0.1 --no-open > $HOME/dsh_web.log 2>&1 &
echo "pid=$!"
sleep 38
echo "alive=$(pgrep -fc 'dsh/lib/bin.js')"
echo "import_fail=$(grep -c 'failed to import' $HOME/dsh_web.log)"
echo "inactive=$(grep -c 'did not activate' $HOME/dsh_web.log)"
grep -o 'http://[^ ]*' $HOME/dsh_web.log | head -1 > $HOME/dsh_url.txt
wc -c < $HOME/dsh_url.txt
# 注：.amd_env 不入库。重建：把 AMD key 写成一行
#   export AMD_RADEON_KEY=<你的key>
# 放在 /data/data/com.termux/files/home/.amd_env 并 chmod 600。
# 也可从 ~/.dsh/.credentials.yaml 的 refs.AMD_RADEON_KEY 提取。
