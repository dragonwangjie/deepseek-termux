# DeepSeek Harness for Android/Termux

> 本站点为 `dragonwangjie/deepseek-termux`（部署记录与脚本集），fork 自 [FunnelCakes/deepseek-harness-android](https://github.com/FunnelCakes/deepseek-harness-android)；上游兼容性修复以原仓库为准。 · This fork carries my deployment runbook and scripts; upstream fixes live in the original repo.

> 在 **Android 手机 Termux 环境** 原生运行 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的一键部署项目 · One-click deployment of DeepSeek Harness on **Android/Termux**.
>
> 点击下方语言标题切换 · Click a language below to view its README.

> [!IMPORTANT]
> **当前最高支持 deepseek-harness rc.7**，向下兼容 rc.6 及更早版本。

> [!TIP]
> **重复部署 / 换机 / 远程部署 / 验证** 请看 [DEPLOY.md](DEPLOY.md)（含 Android 16 + HyperOS 实测记录与保活边界）· For repeat deploys, remote deploys over adb, verification and MIUI keep-alive limits see [DEPLOY.md](DEPLOY.md).

---

<details open>
<summary><b>🇨🇳 中文</b> · 点击收起/展开中文说明</summary>

## 部署速查 / Quick start（2026-10-31 实机验证）

```bash
# 0) 全新安装（干净 Termux）
pkg update -y && pkg install -y git curl
git clone https://github.com/dragonwangjie/deepseek-termux.git
cd deepseek-termux && bash setup.sh

# 1) 日常只记一个命令：拿到当前可用地址（服务已死则当场拉起，20-40s）
durl        # -> http://127.0.0.1:3080/?token=<每次启动重新生成>

# 2) 验证部署是否真的可用（真实 HTTP 往返，不看源码）
sh scripts/verify-deploy.sh     # 期望最后行 fails=0

# 3) 停止（必须先杀守护，否则 3s 内被重拉）
pkill -f supervise.sh && pkill -f bin.js
```

| 要做什么 | 用哪个 |
|---|---|
| 拿可用地址 / 拉活服务 | `durl`（唯一日常入口） |
| 单次前台启动 | `sh ~/run-dsh.sh` |
| 后台自动重拉 | `setsid sh ~/supervise.sh >> ~/supervise.log 2>&1 &` |
| 部署体检 | `sh scripts/verify-deploy.sh` |
| 换机 / 远程部署 / 保活边界 / 卸载 | [DEPLOY.md](DEPLOY.md) |
| 历史踩坑全记录 | [RECOVERY.md](RECOVERY.md) |

> ⚠️ **无开机自启（有意为之）**：`termux:boot` 已卸载、boot 脚本已删。MIUI/HyperOS 燄屏会 Force stop `com.termux`，自启插件也挨不住。需要时用 `durl` 一键拉活。
> ⚠️ **勿缓存 `durl` 输出的 URL**：token 随进程重启变化，旧 token 会 401。

---

## 这是什么

在 Android 手机上原生运行 DeepSeek Harness（`@deepseek-ai/dsh`，DeepSeek 官方的 agent harness，类 Claude Code）。通过 **Web UI**（`http://127.0.0.1:3080`）在手机浏览器里使用，agent 可在手机上真实执行 bash 命令。

> ⚠️ **需要 Termux**：必须在 Android 手机的 Termux 终端里安装运行。**不要用 Google Play 版 Termux**（已过时）。

### 一、安装 Termux

- **F-Droid（推荐）**：<https://f-droid.org/en/packages/com.termux/>
- **GitHub Releases**：<https://github.com/termux/termux-app/releases>

打开 Termux 后执行 `pkg update -y`。

### 二、一键安装

```bash
pkg install -y git
git clone https://github.com/dragonwangjie/deepseek-termux.git
cd deepseek-termux
bash setup.sh
```

> 🇨🇳 **国内用户提示**：`setup.sh` 会自动测速，npm / nodejs.org 较慢时**自动切换到 npmmirror 镜像**（仅本次会话生效，不改全局配置）。若 `git clone` 很慢或超时，请先开代理/TUN，或改用镜像 clone（如 `https://gitclone.com/github.com/dragonwangjie/deepseek-termux.git`）。

### 三、使用

```bash
bash ~/dsh/start_dsh.sh   # 启动并自动拉起浏览器
bash ~/dsh/stop_dsh.sh    # 停止
```

打开 <http://127.0.0.1:3080>，在 **Models** 页填入你的 **DeepSeek API Key**（存于 `~/.dsh/.credentials.yaml`，0600 权限），即可开始。

#### 路径 B：脚本集（要可控重启 / 无人值守推荐）

不想用 `dsh` 全局命令时，本仓库 `scripts/` 提供三个职责单一的脚本（完整说明见 [DEPLOY.md](DEPLOY.md)）：

```bash
PREFIX=/data/data/com.termux/files/usr
cp scripts/run-dsh.sh scripts/supervise.sh $HOME/
install -m 755 scripts/durl $PREFIX/bin/durl

durl      # 唯一日常入口：实测服务可用才输出带 token 的地址；服务死了当场拉起
```

- `run-dsh.sh` 单次前台启动（`--port 3080 --no-open --host 127.0.0.1`）
- `supervise.sh` 守护循环，挂后 3s 重拉，持 `termux-wake-lock`
- `durl` 幂等取地址，token 每次启动重新生成，**不要缓存地址**
- 停止：`pkill -f supervise.sh && pkill -f bin.js`（先杀守护，否则会被重拉）
- 验证部署：`sh scripts/verify-deploy.sh`（做真实 HTTP 往返 + 真实 `link()` 探测，不 grep 源码）

> ⚠️ 本项目**不提供开机自启**：`termux:boot` 方案已移除（脚本删除 + `com.termux.boot` 卸载）。原因见 [RECOVERY.md](RECOVERY.md)：MIUI 燄屏会 Force stop `com.termux`，boot 插件也熬不过，且会被 Force-stop 后收不到 `BOOT_COMPLETED`。

### 四、setup.sh 自动修复的 Android 兼容问题

| 问题 | 现象 | 修复 |
|---|---|---|
| node-pty 无法编译 | `Undefined variable android_ndk_path` | 修补 node-gyp 缓存 `common.gypi` |
| koffi 无法编译 | `statx` 相关 `__u32` 编译错误 | `-target aarch64-linux-android30` |
| npm 拦截构建脚本 | node-pty/koffi 无产物 | `--allow-scripts` 放行 |
| `link()` 被禁（SELinux） | 会话/附件保存、write 工具新建文件报 `EACCES` | 会话/附件发布改 `rename()`；write 新建文件回退"O_EXCL 占位+rename"；附件祖先遍历/清理容忍（`patches/patch-dsh-android-link.js`，幂等） |
| PTY 终端检测失败 | `unsupported on platform android` | subprocess 把 android 视同 linux |
| sharp 无法加载 | `Could not load sharp module` | 安装 `@img/sharp-wasm32` wasm 回退 |
| HMR 启动崩溃 | `--expose-internals is required` | 包装脚本加 `--expose-internals` |
| bash 工具不可用 | `SANDBOX_UNAVAILABLE` | 权限模式设 `danger-full-access` |
| 前端不适配竖屏 | 桌面布局、触控目标小等 | `apply-frontend.sh` 注入移动端 CSS/JS |
| 软键盘遮挡输入框 | 输入法弹出后输入框被键盘盖住 | `visualViewport` 跟随：键盘弹出时整页（含输入框）抬到键盘上方，收回时还原 |
| 局域网 HTTP 缺少 Web Crypto API | `crypto.randomUUID is not a function` | 注入基于 `crypto.getRandomValues()` 的 UUID v4 回退 |
| 上下文大时重进/切回卡顿 | 冷重进、从外部应用切回要等很久 | `apply-js-patches.sh`：history 窗口瘦身（chunk 流过滤+大结果截断）+ 重连增量同步（保留窗口静默补齐） |
| 整页重载重复下载 JS | 每次刷新重下 ~4.7MB bundle | 静态资源与插件 bundle 加 immutable 缓存头 |
| PWA 沉浸模式键盘不跟随 | fullscreen 下软键盘覆盖、视口不收缩，composer 被盖住 | manifest display 改 `standalone`（需重装 PWA，恢复系统栏+正常键盘行为）|

### 五、安全说明

- 服务只监听 `127.0.0.1`（本机），不走局域网。
- API Key 存 `~/.dsh/.credentials.yaml`（0600），不进日志、不进进程环境。
- `danger-full-access` 关闭了进程沙箱（Android 无 bwrap/landlock 替代），agent 可执行任意命令——仅建议个人设备使用。
- 升级 dsh 或 Node 后需重跑 `setup.sh`。

### 六、常见问题

- **页面白屏/打不开**：确认在 Termux 环境；看日志 `~/dsh/storage/dsh.log`。
- **`AbortSignal.any is not a function`**：浏览器过旧，`apply-frontend.sh` 已注入 polyfill。
- **`crypto.randomUUID is not a function`**：局域网 HTTP 或旧版 WebView 不暴露该 API，`apply-frontend.sh` 已注入安全随机 UUID v4 回退。
- **模型没反应**：检查 Models 页 API Key 与 `~/.dsh/.credentials.yaml`。
- **换机/重装**：重跑 `bash setup.sh`。

### 七、作者测试环境与兼容性

- **测试设备**：华为 Mate 60（ALN-AL80），HarmonyOS 4.2.0（build 4.2.0.186），**无 root**，Termux（Node v26，aarch64）。
- **额外实测**：Redmi `25053RT47C`，HyperOS `OS3.0.305.0.WOLCNXM`（MIUI V816），**Android 16**，**无 root**，node v26.12.1 / dsh 0.2.2-alpha.2 —— 该机特有坑（燄屏 Force stop、`ss` 看不到监听、`run-as` 下 HOME 不同）已全部写进 [DEPLOY.md](DEPLOY.md)。
- 不同手机 / ROM 的差异可能导致额外问题，例如：部分 ROM 通过 SELinux 禁用 `link()` 系统调用（会话/附件无法持久化，本脚本已改为 `rename()` 修复）、命名空间沙箱权限不同、bwrap/landlock 是否可用等。
- `setup.sh` 覆盖了通用 Android 场景，但个别机型可能需要额外适配。

**欢迎提 issue / PR 适配更多环境**：如果你在其它品牌、系统版本或 root 状态下遇到问题，欢迎在 [Issues](https://github.com/dragonwangjie/deepseek-termux/issues) 提交，或提交 Pull Request 补充对应机型的修复。

### 参考

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
- [deepseek-harness Discussion #136 — Android/Termux 部署](https://github.com/deepseek-ai/deepseek-harness/discussions/136)
- [deepseek-harness Discussion #248 — Android 禁 hardlink（link→rename 提案）](https://github.com/deepseek-ai/deepseek-harness/discussions/248)
- [Termux Wiki](https://wiki.termux.com/)

</details>

---

<details>
<summary><b>🇬🇧 English</b> · click to expand/collapse</summary>

## What is this

Run [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`@deepseek-ai/dsh`, DeepSeek's official agent harness, Claude Code–like) natively on Android. Use it through the **Web UI** at `http://127.0.0.1:3080` in your mobile browser; the agent can run real bash commands on the phone.

> ⚠️ **Termux required**: install and run inside the **Termux terminal on your Android phone**. Do **NOT** use the Google Play version (outdated).

### 1. Install Termux

- **F-Droid (recommended)**: <https://f-droid.org/en/packages/com.termux/>
- **GitHub Releases**: <https://github.com/termux/termux-app/releases>

Run `pkg update -y` after opening Termux.

### 2. One-click setup

```bash
pkg install -y git
git clone https://github.com/dragonwangjie/deepseek-termux.git
cd deepseek-termux
bash setup.sh
```

> `setup.sh` auto-detects slow npm / nodejs.org and switches to the npmmirror mirror when needed (session-only, doesn't change your global config).

### 3. Usage

```bash
bash ~/dsh/start_dsh.sh   # start & auto-open browser
bash ~/dsh/stop_dsh.sh    # stop
```

Open <http://127.0.0.1:3080>, enter your **DeepSeek API Key** in the **Models** page (stored at `~/.dsh/.credentials.yaml`, mode 0600), and start chatting.

#### Path B: script set (recommended for controlled restarts / unattended use)

```bash
PREFIX=/data/data/com.termux/files/usr
cp scripts/run-dsh.sh scripts/supervise.sh $HOME/
install -m 755 scripts/durl $PREFIX/bin/durl

durl      # the only daily entry point: prints a live token URL, (re)starts the service if dead
```

- `run-dsh.sh` one-shot foreground start · `supervise.sh` restart loop holding `termux-wake-lock`
- tokens are regenerated on every start, so **never cache the URL**
- stop: `pkill -f supervise.sh && pkill -f bin.js`
- verify an install: `sh scripts/verify-deploy.sh` (real HTTP round-trip + real `link()` probe)

> ⚠️ **No boot autostart on purpose.** `termux:boot` was removed (script deleted, `com.termux.boot` uninstalled): MIUI force-stops `com.termux` on screen-off and a force-stopped package never receives `BOOT_COMPLETED`. See [RECOVERY.md](RECOVERY.md).

### 4. Android issues auto-fixed by setup.sh

| Issue | Symptom | Fix |
|---|---|---|
| node-pty fails to build | `Undefined variable android_ndk_path` | patch node-gyp cache `common.gypi` |
| koffi fails to build | `statx` `__u32` compile error | `-target aarch64-linux-android30` |
| npm blocks build scripts | no node-pty/koffi output | allow via `--allow-scripts` |
| `link()` blocked (SELinux) | `EACCES` saving sessions/attachments, and when `write` tool creates a new file | session/attachment publish uses `rename()`; new-file write falls back to "O_EXCL reserve + rename"; attachment ancestor-walk & cleanup tolerate EACCES/ENOENT (`patches/patch-dsh-android-link.js`, idempotent) |
| PTY terminal detection fails | `unsupported on platform android` | treat android as linux in subprocess |
| sharp fails to load | `Could not load sharp module` | install `@img/sharp-wasm32` wasm fallback |
| HMR crashes on start | `--expose-internals is required` | wrapper script adds `--expose-internals` |
| bash tool unavailable | `SANDBOX_UNAVAILABLE` | permission mode `danger-full-access` |
| Frontend not mobile-ready | desktop layout, small touch targets | `apply-frontend.sh` injects mobile CSS/JS |
| Soft keyboard covers the input | input box hidden behind the IME when it opens | `visualViewport`-driven follow: page (incl. input) lifts above the keyboard on open, restores on close |
| Web Crypto API missing over LAN HTTP | `crypto.randomUUID is not a function` | inject a UUID v4 fallback based on `crypto.getRandomValues()` |
| Lag re-entering / switching back with big context | cold re-entry and app-return stall for seconds | `apply-js-patches.sh`: slim history windows (chunk-stream filter + big-result truncation) + incremental reconnect sync (keep window, quiet catch-up) |
| Page reload re-downloads JS | ~4.7MB bundles re-fetched every refresh | immutable cache headers on static assets & plugin bundles |
| PWA immersive-mode keyboard not followed | soft keyboard overlays without shrinking the viewport; composer stays covered | manifest `display` → `standalone` (reinstall the PWA; restores system bars + normal keyboard behavior) |

### 5. Security notes

- The service listens only on `127.0.0.1` (local, not LAN).
- API Key is stored at `~/.dsh/.credentials.yaml` (0600), never in logs or process env.
- `danger-full-access` disables the process sandbox (no bwrap/landlock on Android); the agent can run any command — personal devices only.
- Re-run `setup.sh` after upgrading dsh or Node.

### 6. FAQ

- **Blank screen / cannot open**: make sure it's Termux; check `~/dsh/storage/dsh.log`.
- **`AbortSignal.any is not a function`**: old browser; `apply-frontend.sh` injects a polyfill.
- **`crypto.randomUUID is not a function`**: LAN HTTP and older WebViews may not expose the API; `apply-frontend.sh` injects a secure UUID v4 fallback.
- **Model not responding**: check the API Key in Models page and `~/.dsh/.credentials.yaml`.
- **Reinstall / new device**: re-run `bash setup.sh`.

### 7. Author's test environment & compatibility

- **Tested device**: Huawei Mate 60 (ALN-AL80), HarmonyOS 4.2.0 (build 4.2.0.186), **no root**, Termux (Node v26, aarch64).
- Different phones / ROMs may behave differently, e.g. some ROMs block the `link()` syscall via SELinux (sessions/attachments fail to persist — this script switches to `rename()` to fix it), namespace-sandbox permissions vary, and bwrap/landlock may or may not be available.
- `setup.sh` covers the common Android cases, but specific devices may need extra tweaks.

**Issues & PRs welcome**: if you hit a problem on another brand / OS version / root state, please open an [issue](https://github.com/dragonwangjie/deepseek-termux/issues) or submit a pull request with a fix for your environment.

### References

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
- [deepseek-harness Discussion #136 — Android/Termux deployment](https://github.com/deepseek-ai/deepseek-harness/discussions/136)
- [deepseek-harness Discussion #248 — hardlinks blocked on Android (link→rename proposal)](https://github.com/deepseek-ai/deepseek-harness/discussions/248)
- [Termux Wiki](https://wiki.termux.com/)

</details>

---

## License

MIT
