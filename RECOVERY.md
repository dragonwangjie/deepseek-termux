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
