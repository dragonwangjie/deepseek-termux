# 部署手册 / Deployment Runbook

面向后续重复部署（换机、重装、恢复）。所有命令均在下述环境实测通过。

实测环境（2026-10-31）：
- 设备 Redmi `25053RT47C`，HyperOS `OS3.0.305.0.WOLCNXM`（MIUI `V816`），**Android 16**，**无 root**
- Termux 运行时：node `v26.12.1`、npm `11.21.1`、git `2.56.0`、curl `8.23.0`
- dsh 版本：`0.2.2-alpha.2`（`engines.node >= 24.9.0`），装于 `~/dsh022`，依赖 197 个包
- 数据目录 `~/.dsh/`（`logs profiles sessions storages`，`.credentials.yaml` 权限 `-rw-------`）

> 与 README 的分工：README 讲 **setup.sh 一键装**（上游通用路径）；本文讲 **本机实际布局**、**从工作站远程部署**、**验证** 与 **MIUI 保活边界**。

---

## 0. 两种安装路径，选一个

| 路径 | 适合 | 入口 |
|---|---|---|
| A. `setup.sh` 全新安装 | 新机器 / 干净 Termux | `~/dsh/start_dsh.sh` |
| B. 本仓库脚本集（推荐给自己复现） | 已有 `~/dsh022` 安装，要可控重启 | `durl` |

两者不要混用同一端口（都是 3080）。切前先 `bash stop_dsh.sh` + `pkill -f bin.js`。

---

## 1. 路径 A：全新安装（无 root Termux）

```bash
pkg update -y
pkg install -y git curl
git clone https://github.com/dragonwangjie/deepseek-termux.git
cd deepseek-termux
bash setup.sh
```

`setup.sh` 依次处理：构建依赖 -> node-gyp `common.gypi` 修补 -> `--allow-scripts` 放行安装 -> `link()`->`rename()` 补丁 -> sharp wasm 回退 -> 移动端前端注入 -> 静态资源缓存头。全程 10-25 分钟（瓶颈在 node-pty/koffi 编译，不是网络）。

模型 Key：<http://127.0.0.1:3080> -> **Models** 页填 DeepSeek API Key，落盘 `~/.dsh/.credentials.yaml`（0600，不进日志、不进进程环境）。

---

## 2. 路径 B：脚本集布局（本机现状）

三个脚本职责不重叠。仓库内 -> 设备落地：

| 仓库 | 设备 | 作用 |
|---|---|---|
| `scripts/run-dsh.sh` | `$HOME/run-dsh.sh` | 单次前台启动，`exec` node，参数固定 `web --port 3080 --no-open --host 127.0.0.1` |
| `scripts/supervise.sh` | `$HOME/supervise.sh` | 守护循环：挂后 3s 重拉，持 `termux-wake-lock`，日志 `~/supervise.log` |
| `scripts/durl` | `$PREFIX/bin/durl` | **唯一日常入口**：实测服务可用才输出地址；不可用则当场拉起（最多 12 次 x 3s），并保证只跑 1 个守护 |

安装（在 Termux 里）：

```bash
PREFIX=/data/data/com.termux/files/usr
H=$HOME
cp scripts/run-dsh.sh scripts/supervise.sh $H/
install -m 755 scripts/durl $PREFIX/bin/durl
chmod 700 $H/run-dsh.sh $H/supervise.sh
```

日常三条命令够用：

```sh
durl                 # 拿可用地址（服务死了自动拉活）
pkill -f supervise.sh; pkill -f bin.js   # 停：先杀守护，否则会被重拉
tail -20 ~/dsh_web.log                    # 看服务侧日志
```

`durl` 输出形如 `http://127.0.0.1:3080/?token=<32位>`。token 每次启动重新生成，地址只能现取，不要缓存。

> 开机自启已按要求移除：`~/.termux/boot/` 已删、`com.termux.boot` 已 `pm uninstall`。**不存在 BOOT_COMPLETED 触发器**，服务只由 `durl` 按需拉起。`scripts/start-dsh-boot.sh` 已废弃，不要推回设备；历史见 `RECOVERY.md` 末尾。

---

## 3. 从工作站远程部署（无 root，走 `run-as`）

Termux 私有目录对 adb 不可见，必须借 `run-as com.termux`。推脚本进去的标准姿势（base64 过 stdin，避开引号地狱与 CRLF）：

```bash
adb connect 127.0.0.1:5555
B=$(base64 -w0 local.sh)
adb -s 127.0.0.1:5555 shell "run-as com.termux sh -c 'echo $B | base64 -d > /data/data/com.termux/in.n; chmod 700 /data/data/com.termux/in.n; sh /data/data/com.termux/in.n; rm /data/data/com.termux/in.n'"
```

三个必踩的坑（均实测）：
1. `run-as` 下 **HOME 是 `/data/user/0/com.termux`，不是真实 $HOME**。脚本一律用绝对路径，或显式 `export HOME=/data/data/com.termux/files/home`。否则探测脚本会全 0 假阴性。
2. 必须 `export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib`，否则 node 直接起不来。
3. 写 `目标.新` 再 `mv` 覆盖，不要直接 `>` 目标（半写状态会让下次启动读到截断脚本）。

`adb push` 进不了私有目录，别试；`run-as` + base64 是唯一稳的。另：`am broadcast -a android.intent.action.BOOT_COMPLETED` 会被系统拒（`SecurityException ... uid=2000`），别指望用 adb 验证开机自启。

---

## 4. 部署后验证（`scripts/verify-deploy.sh`）

```sh
sh verify-deploy.sh
```

6 项功能校验（不是 grep 源码）：node/dsh 版本门槛、`run-dsh.sh` 语法、服务 HTTP 状态、token 换 cookie 能否真进 UI、`link()` 是否被 SELinux 禁（决定要不要 rename 补丁）、当前守护与 node 进程数。

手工等价验证（最小两条）：

```sh
u=$(durl); curl -s -c /data/data/com.termux/j -b /data/data/com.termux/j -L -o /dev/null \\
  -w "final=%{http_code} redirects=%{num_redirects}\\n" "$u"; rm -f /data/data/com.termux/j
```

预期输出（本机实测）：

```
OK   node 26.12.1 meets engines floor 24.9.0
OK   dsh 0.2.2-alpha.2
OK   lib/bin.js present
OK   run-dsh.sh syntax
OK   supervise.sh syntax
OK   durl installed in /data/data/com.termux/files/usr/bin
OK   login round-trip final=200 redirects=1
WARN link() blocked by SELinux -> apply patches/patch-dsh-android-link.js ...
OK   one supervisor
OK   one dsh node process

== fails=0 warns=1
```

那条 `WARN link() blocked` 在 HyperOS/Android 16 上是**预期**（SELinux 禁 hardlink，计 WARN 不计 FAIL）：意味着会话/附件持久化需要 `patches/patch-dsh-android-link.js` 的 rename 回退。只有 `fails=0` 才算部署成功。

**判定只看这一行**：`final=200 redirects=1`。裸 curl 不带 cookie jar 得到 401/303 是预期行为，不是故障；`/api/sessions` 之类路径 404 同理，不作判据。验完删掉 cookie 文件（内含会话 cookie）。

---

## 5. 保活边界（MIUI/HyperOS，无 root 无解）

已证实硬限制：燄屏后 `com.miui.powerkeeper` 的 **LockScreenClean** 会 `Force stopping com.termux`，node 与 supervise **同时** SIGKILL，`dsh_web.log` 里零 error（不是自崩）。证据与时间线见 `RECOVERY.md`。

已试过、**无效**：`RUN_ANY_IN_BACKGROUND=allow`、Doze 白名单、`stay_on`、phantom process 限制关闭、`termux-wake-lock`。LockScreenClean 不看这些；相关开关 adb 里搜不到（global/secure/system 均无）。

可用出路，按性价比排序：
1. **插电 + 设置->应用管理->Termux->电池->省电策略=无限制**，并在最近任务里下拉锁定 Termux。唯一的 MIUI 官方口子。
2. 接受“燄屏即停”，把 `durl` 当幂等入口：任何时候一条命令保证拿到活地址。
3. 要真常驻：需要**带前台服务的 apk**（或 root）。普通 Termux 进程做不到，这不是脚本能解的问题。

## 6. 卸载 / 重置

```sh
pkill -f supervise.sh; pkill -f bin.js
rm -f $PREFIX/bin/durl $HOME/run-dsh.sh $HOME/supervise.sh $HOME/dsh_url.txt $HOME/dsh_web.log $HOME/supervise.log
# 连数据一起清（含 API Key 与会话，谨慎）：
rm -rf $HOME/.dsh
```

仓内脚本与文档保留，重跑第 2 节那三行即可复现。
