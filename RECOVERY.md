# dsh 重启后恢复（2026-10-30）

前提：设备已开机、能打开 Termux/Operit 任一 App。

## 一步恢复（在新会话的 terminal 里跑）
```sh
adb connect 127.0.0.1:5555
timeout 200 adb -s 127.0.0.1:5555 shell run-as com.termux sh /data/data/com.termux/files/home/start_web.sh
```
期望输出：`amd_key_set=yes`、`alive=1`、`import_fail=0`、`inactive=0`。

## 取新地址（token 每次启动会变）
```sh
timeout 40 adb -s 127.0.0.1:5555 shell run-as com.termux cat /data/data/com.termux/files/home/dsh_url.txt
```
浏览器打开输出的 URL → Models 页应有 AMD Radeon × 6 模型。

## adb 连不上时
1. `adb devices` 看是否需重新配对（无线调试端口会变）；
2. 有 root 就跳过 adb：直接 shell 工具 `su 0 run-as com.termux sh /data/data/com.termux/files/home/start_web.sh`（不行则 `su 0 sh -c 'HOME=/data/data/com.termux/files/home; . $HOME/.amd_env; ...'` 手动同构）；
3. .amd_env / start_web.sh 都在 Termux home，重启不丢。

## 验证通过标准（上一轮实测值）
headless 出词 + projcache lastUsed={provider:radeon}；web 服务 401=正常（token 保护）。

## curl 验证要点（浏览器自动做，curl 要手动）
token 走 query 只负责 303 换 HttpOnly cookie，直接带 token 请求仍 401。两步：
```sh
curl -s -c /sdcard/Download/tmp/ck.txt -o /dev/null "<URL>"     # 领 cookie
curl -s -b /sdcard/Download/tmp/ck.txt -o /dev/null -w '%{http_code} %{size_download}\n' http://127.0.0.1:3080/
# 期望：200 与 ~59000 字节；验完 rm ck.txt（内含 token）
```
## 开机自启（Termux:Boot）

Termux 是 debug 签名构建（0.119.0-beta.3, flags 含 DEBUGGABLE），所以 Termux:Boot 只能取 GitHub release 的 +github.debug.apk；F-Droid 版签名不匹配。v0.8.1 sha256=97e6d336f05b59f7cb25e8efa7173e0a6e665f3022b75c6d55a69b6399ecacc8

无 root 时装 APK 要先解三个开关，否则 INSTALL_FAILED_USER_RESTRICTED：

    adb shell settings put secure install_non_market_apps 1
    adb shell settings put global verifier_verify_adb_installs 0
    adb install -r -g -t tb.apk
    adb shell am start -n com.termux.boot/.BootActivity   # 新装后起一次注册接收器

自启脚本 ~/.termux/boot/start-dsh.sh 两行：

    #!/data/data/com.termux/files/usr/bin/sh
    sh /data/data/com.termux/files/home/start_web.sh > /data/data/com.termux/files/home/boot_dsh.log 2>&1

坑：必须 sh 调用且 start_web.sh 本身 chmod 700，用 exec 会 can't execute: Permission denied；路径写绝对，$HOME 在传输层会丢；run-as 里不能 bash（SELinux）。

## 2026-10-30 21:00 实测：重启后损失清单与修正

**adb 持久化成功**：settings global adb_wifi_enabled=1 + /data/misc/adb/adb_keys 生效后，重启后 `adb connect 127.0.0.1:5555` 免配对直连。

**开机自启其实触发了**（boot_dsh.log mtime = 开机后 19 秒），但那次 dsh 起来又退出（alive=0 inactive=1，日志里没有 "did not activate" 字串，估为早期依赖未就绪）。教训：判断自启要看 boot 日志 mtime，不能只看当前进程。已将 ~/.termux/boot/start-dsh.sh 改为重试循环（最多 5 次，每轮后 grep alive=1，sh -n 已校验）。

**宿主机 Ubuntu /root 每次重启清空**（proot 非持久层）：`/root/dsh` 客户端、`/root/.ssh`、`/tmp/*` 全丢。dsh 服务端在 Termux home 的 `dsh022/`（不是 `dsh/`），重启不丢；宿主机侧工具每次重启后需重建。

**验证手段修正**：设备 shell 无 curl（toybox 不含）；从宿主机验证走 `adb forward tcp:13080 tcp:3080` 再 curl，期望 `home=200 bytes=~59000`。`pgrep -f dsd.py` 会把 adb 自身命令行算进去（假阳性），探进程要用 `pgrep -af 'ds[d].py'` 字面量打散或 /proc/*/cmdline 扫描 + 端口实探。

## 2026-10-31 定性：dsh 后台被冻结（非启动失败）

症状：启动脚本全部成功（alive=1 / inactive=0 / 日志出 URL），但 HTTP 永远 000；`ss` 显示 127.0.0.1:3080 LISTEN，而 node 进程 utime 4 秒零推进、卡在 `do_epoll_wait`。

**根因：MIUI 将后台 Termux 进程冻结**。socket 已 listen 但 accept 循环不被调度。

**验证**：`am start -n com.termux/.app.TermuxActivity` 把 Termux 切前台后 12s 内：
- 直接探 3080 → `401`（token 保护，正常）
- 两步验证 → `cookie=303` + `home=200 bytes=59623`（基准值）

**结论**：服务本身没问题，不用改 dsh 启动参数。要长驻必须保活：
1. 已做：`dumpsys deviceidle whitelist +com.termux`、`appops set com.termux RUN_ANY_IN_BACKGROUND allow`、`WAKE_LOCK allow`；
2. 未解决：`termux-wake-lock` 从 run-as 上下文调用返回 255（需要 Termux 自己的 session），所以必须从真 Termux 会话或通知栏启动；
3. 已部署 `~/.termux/boot/start-dsh.sh` → `setsid supervise.sh`（每 20s 巡检，不在则重起）；注意 supervisor 只能防被杀，防不了冻结。

**工具坑（本轮反复踩）**：
- 设备 `netstat -ltn` 会假阴性（看不到 3080），用 `ss -ltn` 或 `awk ''NR>1 && $2 ~ /:0C08$/ && $4==0A'' /proc/net/tcp`；hex(3080)=0C08。
- `pkill -f X` 在 `run-as sh -c` 里会匹配到自身命令行而自杀 → 用字符类 `[d]sh/lib` 或先写脚本文件再执行。
- run-as 不能写 /data/local/tmp（uid 不同）；写 Termux home 用 base64 内联，嵌套引号会被吞。
- `run-as com.termux cat 相对路径` 不行（cwd 不确定），一律用绝对路径；而 `ls -l 绝对路径` 有时又报 Permission denied，同一个 `sh -c` 里反而正常。
- super_admin:terminal 与 read_file 会整片挂（root executor unavailable），兼用 code_runner:run_python + subprocess adb 可用。
- 宿主机验证路径：`adb forward tcp:13080 tcp:3080` 后 curl 127.0.0.1:13080；但**设备冻结时 forward 也会 000**，别误判为网络问题。

## 2026-10-31 09:15 冻结问题已解（stayon + bucket + 重启循环）

上一节定性后验证：`svc power stayon true`（`settings put global stay_on_while_plugged_in 15`）+ `am set-standby-bucket com.termux active`（bucket=5）+ supervise.sh 20s 巡检，三项同时生效后：
- Termux 完全后台（焦点在淘宝）连续 3 次 `401`（不冻结）
- 完整验证：`cookie=303 → home=200 bytes=59623 → <title>DeepSeek Harness`
- KEYCODE_SLEEP 进 Dozing 后 90s：仍 `401`，pid 不变

未覆盖：长时间深度 doze（>10min、拔电）与下次真实重启后的自启（boot 已改为 `exec sh supervise.sh` 前台阻塞，为了在 Termux:Boot 释放 wakelock 前不退出）。

### 无法绕过的限制
- `am broadcast BOOT_COMPLETED` 现在报 `SecurityException: not allowed to send broadcast from uid 2000`（06:08 那次成功是实例差异），所以 boot 脚本只能靠真重启验证。
- `am startservice com.termux/.app.TermuxService` 从 adb 报「Requires permission not exported from uid 10559」；从 `run-as` 报「Can't start from invalid source: 10559」→ **termux-wake-lock 无法外部触发**，日志显示它 ACQ 17s 后必 REL（com.termux.boot 退出即释放）。
- 因此保活靠 stayon+bucket+supervise，而不是 wake-lock。

### 开机自启现状（下次重启生效）
~/.termux/boot/start-dsh.sh：`exec sh supervise.sh >> supervise.log 2>&1`（exec 不后台，阻止 wakelock 释放）
start-dsh 依赖 supervise.sh：每 20s 检查 `pgrep -f dsh/lib/bin.js`，没起就 `setsid node … web --port 3080`。

## 2026-10-31 10:5x 补修：`--no-open` 与拔电 Doze 告警

### `--no-open` 必须加
supervise.sh 的启动行现为：`setsid $BIN $A web --port 3080 --no-open --host 127.0.0.1 >> dsh_web.log 2>&1 </dev/null &`
原因：dsh 默认会“打开默认浏览器”，在 Termux/Android 后台调起浏览器会阻塞，导致 node 打印了 URL 却未完成 listen（grep /proc/net/tcp 的 :0BF0 为空，curl=000）。加 `--no-open` 后后台也能正常 bind（self=401）。

### stay_on 仅插电生效
`stay_on_while_plugged_in=15` 只在 AC/USB 供电时阻止 suspend。设备拔电后（实测 AC powered:false, 电 53%）会进 Dozing，node 会被 MIUI 冻结，服务不响应。要长期无人值守必须：插着电 + 亮屏，或 root 后加 `dumpsys deviceidle whitelist +com.termux` / `settings put global device_idle_mode light`。

### 当前交还状态
- node 监听 127.0.0.1:3080，supervise 守护已接管（每 20s 巡检）
- 最新 URL 已写入 `~/dsh_url.txt`（token 见该文件）；需登录，凭据存 ~/dsh-creds.json
- 无法在本会话验证真重启自启（BOOT_COMPLETED 广播被系统拒）；boot 脚本已改为 exec 前台阻塞，下次真实开机生效
