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

## 2026-10-31 11:4x 拔电冻结定论（无 root 不可解，插电即解）

实验链（node 存活 State=S TracerPid=0，即未杀进程、未 ptrace 冻）：
1. `dumpsys deviceidle whitelist +com.termux` 成功写入 /data/system/deviceidle.xml（uid 2000 即可，重启保留），`com.termux.boot` 同时在列 → 无效，熄屏 000
2. `settings put global settings_enable_monitor_phantom_procs false` + `max_phantom_processes 65535` → 无效
3. `appops set com.termux RUN_ANY_IN_BACKGROUND allow` 已生效 → 无效
4. `dumpsys deviceidle force-idle` 进深度 idle 时（插电）反而存活；拔电熄屏 100s 必 000
→ 结论：冻结源 = CPU suspend（suspend-to-RAM）。`stay_on_while_plugged_in=15` 插电时禁止 suspend，故插电即稳。无 root 无法持有永久 wakelock（termux-wake-lock 在 Termux:Boot 退出时 17s 必放，`am startservice` 被拒，SYSTEM_EXEMPTED op 不存在）。

### 无人值守最终配方
插电 + 屏幕可关（stayon 只保 CPU，省电可接受）；supervise.sh 20s 巡检兼 socket 丢失自愈（重 spawn 会换 token，dsh_url.txt 随之刷新）。
所有已应用的持久开关（重启后保留）：stay_on=15、deviceidle 白名单×2、phantom 监控关、RUN_ANY_IN_BACKGROUND allow、standby bucket active（bucket 不持久，重启后可再 `am set-standby-bucket com.termux active`，非必需）。

## 2026-10-31 12:0x 守护脚本收编
supervise.sh 新版（仓库 scripts/ 有源）：spawn 后 15s + 每循环 refresh_url，自动维护 ~/dsh_url.txt（重启/重拉换 token 不再需要手动刷）；兼带修掉重复 --no-open。boot 脚本同步存 scripts/start-dsh-boot.sh。已装机并实测：删 dsh_url.txt 后 25s 自动重建。

## 2026-10-31 15:5x dshurl 取地址（两处修正）
坑：Termux 的 bash 是 login shell，只读 ~/.bash_profile，不读 ~/.bashrc → 光写 .bashrc 无效。
修：① 新建 ~/.bash_profile（source .bashrc + 函数定义）② 同时把可执行脚本装到 $PREFIX/bin/dshurl（PATH 永久含此目录，任意 shell 可用，不依赖 rc）。
实测 $PREFIX/bin/dshurl 直接打印完整 URL；bash -lc "type dshurl" 也确认函数加载。
注意：已开的 Termux 会话需新建会话才加载函数；二进制方式无需新会话。

## 2026-10-31 16:0x 两个真 bug 修复
1. dshurl 不起作用：Termux bash 是 login shell 只读 ~/.bash_profile（不读 .bashrc）。已建 .bash_profile，并把可执行脚本装到 $PREFIX/bin/dshurl（PATH 永久含此目录，不依赖 rc，任意 shell 可用）。仓库 scripts/dshurl 存源。
2. 守护假活：旧 supervise.sh 用 pgrep 判存活，但 node 进程存活而 3080 未监听时会永远不重拉（实现：pid 17287 State=S、NO_LISTEN、svc=000）。新版改为 curl HTTP 探测 + 失败则 kill 重拉 + 每 5s 最多 6 次确认监听（日志 probe n=N）。实测：spawn 15:58:13 → probe n=1（10s 内就绪）→ svc=401，dshurl 与 dsh_url.txt 同步为新 token。
坑备忘：用 adb 做 `pkill -f supervise.sh` 会匹配到自身命令行把启动弄死，要放进文件脚本里跑。

## 2026-10-31 16:2x NOT_READY 根因：MIUI LockScreenClean
证据：`logcat -b system` 16:12:43 `ActivityManager: Force stopping com.termux.boot ... LockScreenClean` + `Killing ...com.termux.boot/u0a559 (adj 905): stop com.termux.boot due to LockScreenClean`；时间线与 supervise.log 的 spawn 16:03:52/16:07:39/16:12:03 完全对应，且 dsh_web.log 零 error（node 不是自崩，是被 SIGKILL）。
含义：**燄屏就 Force stop 整个 com.termux uid**——node 与 supervise.sh 同灭，无人重拉，直到用户再次打开 Termux。
已没牙的招：RUN_ANY_IN_BACKGROUND=allow、doze 白名单、stay_on=15、phantom 关——LockScreenClean 不看这些。
可写开关搜索结果为 null（global/secure/system 无 lock_screen_clean 类键，由 com.miui.powerkeeper 内部控制，adb 无法改）。
有效出路（三选一，无 root）：
① 应用管理→Termux→电池→省电策略=无限制 + 最近任务下拉锁定 Termux（MIUI 官方正规口子）
② 保活靠不燄屏：插电（stay_on=15 已开，插电时屏幕不自动熄）
③ 将 `dshurl` 当手动拉起入口：它现在从 dsh_web.log 现推 URL（文件没了也能出），若服务已死则提示 `sh ~/supervise.sh`
无头守护真正可行方案：需单独前台服务 apk（或 root），普通 Termux 进程撑不过 LockScreenClean。

## 2026-10-31 16:4x NOT_READY 彻底修：新增 durl（自带拉起 + 真有效性校验）
之前 NOT_READY 两层原因：
1. 旧 bash 会话缓存了旧函数（函数只存内存，改文件不生效）——已删函数、且改用新命令名 `durl` 避开缓存（dshurl 已软链到 durl）。
2. 旧 dshurl 只看文件里有无 URL，不验服务死活；加上早期 supervise 里 `: > $L` 会清日志 → 退路也被抹掉。
durl 行为：先用 curl 实测 `/?token=` 必须返回 303/200 才输出（401=服务活但 token 旧，不算通过）；不通过则当场 pkill+run-dsh.sh 拉起，每 3s 重试最多 12 次，成功后原子写 dsh_url.txt 并顺手带起 supervise.sh。
实测（进程全杀 + 删文件的最坏情况）：`durl` → “not responding, starting” → 输出可用 URL，rc=0。
仍存的硬限制：MIUI LockScreenClean 燄屏 Force stop com.termux（logcat 已证），因此服务会时好时坏；`durl` 的意义是把“看状态”变成“一条命令保证拿到可用地址”。真正保活需无头前台服务 apk 或 root。

## 2026-10-31 17:0x 登录链路真实验证（cookie jar）
`curl -c jar -b jar -L "<带 token 的 URL>"` → final=200, url_effective=http://127.0.0.1:3080/, redirects=1（token 换 cookie 后拿到 UI）。
之前用裸 curl 测得 401/303 的原因是未带 cookie，不是服务故障；/api/sessions 等是我猜的路径（404），不计入结论。
结论：`durl` 输出的地址在手机浏览器直接可用（已确认服务侧 200）。

## 2026-10-31 16:5x 已删除 termux:boot 自启（用户要求）
删除：`$H/.termux/boot/start-dsh.sh` 与 `.termux/boot/` 目录（实测 ls 已 No such file）。
残留检查：.bashrc / .bash_profile 无 supervise 引用（none_in_shell_rc）；.termux/ 只剩 termux.properties。
服务当前仍在跑（node 31285）——只删自启，不影响已运行实例。
现行启动入口只剩 `durl`（实测不响应时自行拉起）。
仓内 `scripts/start-dsh-boot.sh` 已废弃，仅作历史参考，不得再推回设备。
com.termux.boot 包仍在设备上（现为死路径，无任何脚本可执行）；可 `pm uninstall com.termux.boot` 进一步清掉。
