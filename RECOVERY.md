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
