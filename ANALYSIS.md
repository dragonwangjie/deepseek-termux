# deepseek-harness-android 分析报告

分析时间：2026-10-29 · 对象 commit：52b2ca0（main, 35 commits）
本地副本：/sdcard/Download/projects/deepseek-harness-android

## 1. 项目定位

不是 fork，是**外部补丁集 + 一键安装器**。上游 @deepseek-ai/dsh（DeepSeek 官方 agent harness）照常从 npm 装进 Termux 全局 node_modules，本项目在它装好后**就地改写已安装的 lib/*.js**。

规模：19 个跟踪文件 / 2147 行 / 156 KB。语言：Shell + Node JS + 5 个 .patch。MIT。作者 FunnelCakes(34) + wozpren(1)。

## 2. 文件与执行流

```
setup.sh (329 行, 10 步)
  1/8 pkg install cmake clang make binutils pkg-config python nodejs
      智能换源：is_slow() 测速 -> 慢则本次会话切 npmmirror（不改全局配置）
  2/8 node-gyp install 拉 headers -> 修补缓存 common.gypi（补 android_ndk_path，修 node-pty）
  3/8 npm i -g --allow-scripts + -target aarch64-linux-android30（修 koffi statx）
      + 注入 spawn.h bionic shim（Issue #4）
  4/8 后端补丁：4a session link->rename / 4b attachment link->rename
      4e node patches/patch-dsh-android-link.js（fs-local no-replace + 附件遍历容忍）
  5/8 @img/sharp-wasm32 wasm 回退（android-arm64 无原生 sharp）
  6/8 重写 /usr/bin/dsh 包装脚本，加 --expose-internals（HMR 必需）
  7/8 拷 start/stop 脚本 + 写 cordis.patch.yml: mode: danger-full-access
  8/8 bash apply-frontend.sh
  9/9 bash apply-js-patches.sh

apply-frontend.sh (108)  -> 就地注入上游 HTML：mobile.css(231) + mobile.js(299)
                             + manifest display: fullscreen -> standalone
                             + AbortSignal.any / crypto.randomUUID polyfill
apply-js-patches.sh (45) -> patch -p1 打 5 个补丁到 dsh/node_modules/@deepseek-ai/*
                             幂等三重检：先 --dry-run -R 判已应用，再 --dry-run 判可应用
patches/patch-dsh-android-link.js (251) -> 三处 link() 版本兼容幂等修补，支持 --root 跨机
start_dsh.sh(42)/stop_dsh.sh(7)/restart_dsh_now.sh(28) -> 端口 3080，日志 ~/dsh/storage/dsh.log
docs/index.html(202) -> Pages 落地页；config/cordis.patch.yml -> 权限模式模板
```

## 3. Android 兼容修复清单（14 项）

| 层 | 问题 | 手段 |
|---|---|---|
| 构建 | node-pty: android_ndk_path 未定义 | 补 node-gyp 缓存 common.gypi |
| 构建 | koffi: statx __u32 / <spawn.h> 缺失 | android30 target + $PREFIX/include + spawn.h shim |
| 构建 | npm 拦截 postinstall | --allow-scripts |
| 运行时 | SELinux 全局禁 link() -> EACCES | 会话/附件改 rename()；write 新建文件退化为 O_EXCL 占位+rename |
| 运行时 | PTY 检测 unsupported on platform android | subprocess 把 android 视同 linux |
| 运行时 | sharp 无 android-arm64 预编译 | @img/sharp-wasm32 wasm 回退 |
| 运行时 | HMR 需 --expose-internals | dsh 包装脚本 |
| 运行时 | SANDBOX_UNAVAILABLE（无 bwrap/landlock） | danger-full-access |
| 运行时 | 局域网 HTTP 无 Web Crypto | crypto.randomUUID polyfill |
| 性能 | 大上下文冷重进卡顿 | history 窗口瘦身（chunk 流过滤 + 大结果截断） |
| 性能 | 切回前台卡顿 | 重连增量同步（保留窗口静默补齐） |
| 性能 | 每次刷新重下 ~4.7MB bundle | 静态资源/插件 bundle immutable 缓存头 |
| UI | 竖屏不适配 | 注入 mobile.css/js |
| UI | 软键盘遮挡 / PWA 全屏不跟随 | visualViewport 跟随 + manifest standalone |

## 4. 补丁目标（5 个上游包）

dsh-host-apiproxy / dsh-client-runtime / dsh-client-connection / dsh-host-frontend-static / dsh-client-modules
—— 全以 rc.6 文本为锚点；dry-run 预检，不匹配时报 FAIL 而非破坏安装。

## 5. 更新状态：已落后上游两个大版本（重要）

- 仓库最后提交 2026-08-18（已 71.8 天无更新），README 声明最高支持 rc.7
- 上游 deepseek-ai/deepseek-harness 已到 dsh-v0.2.1-rc.4 / v0.2.2-alpha.2（2026-10-28）
- 4 个开放 issue 全部指向 0.2.x 适配缺口：

| # | 日期 | 内容 | 影响 |
|---|---|---|---|
| #6 | 10-07 | 0.2.x 新增硬依赖 node-addon-require-builtin，无 android-arm64 预编译 -> dsh web 启动即 fatal（No usable native binding found）；报告人已附补丁与脚本 | **阻断性**：现 setup.sh 装 0.2.x 直接起不来 |
| #7 | 10-08 | patch-dsh-android-link.js 的 already-fixed 判定只看调用点 rename(，不校验导入行；「调用已改但 import 缺 rename」被误报 [OK]，运行时 ReferenceError: rename is not defined | 误报掩盖真故障 |
| #5 | 08-22 | PR：持久化 ripgrep 修复 + 04 静态缓存补丁适配 0.1.1-rc.2 | 未合并，挂 2 个月 |
| #8 | 10-18 | 纯 AI 写的 0.2.x 现场记录（HONOR / Android 16 / Node 26），无人类编辑 | 参考素材，非补丁 |

**判定**：现在直接 bash setup.sh（npm 会装 0.2.x）预期失败。可用路径：把 dsh 锁到 rc.7，或采 #6 附的补丁。恢复需：1) 合 #6 的 node-addon-require-builtin 处理 2) 修 #7 双重判定 3) 重建 5 个 .patch 的行锚点。

## 6. 质量评价

做得好：set -euo pipefail 全覆盖；补丁三重复幂等（dry-run -R / 正则标记 / grep 前置）；换源仅本次会话不污染全局；link 修复独立成文件、支持 --root 跳机、注释写明根因与上游 discussion 编号；README 标明测试机型（华为 Mate 60 / HarmonyOS 4.2.0 / 无 root / Node v26）并如实写出 danger-full-access 的安全含义。

薄弱：补丁按文本锚点匹配，上游一行改动即整批失效（现已失效）；无 CI / 无测试 / releases 空（仅 v1.0.0 tag）；仅覆盖单一机型。

## 7. 本地保存结果 + Android 侧 git 踩坑（已验证）

保存位置：
- 仓库：/sdcard/Download/projects/deepseek-harness-android（main=52b2ca0，35 commits，git fsck 零输出，工作树 19 文件，518 KB）
- 离线包：/sdcard/Download/projects/deepseek-harness-android-all.bundle（85 KB，含全部分支）

在 sdcard 上放可用 git 仓库的 4 个必要条件（本次逐条踩实）：
1. 不要在 proot 里直接 git clone 到 /sdcard：pack 临时文件被转成 .l2s.tmp_* 符号链接，改名失败；误删这些链接会连对象库一起丢（本次首次尝试即损坏，需重克隆）。
2. 正确姿势：先 clone 到 Linux 侧 $HOME（f2fs），tar czf 打包，再由 terminal_exec（真实挂载）解包到 /sdcard。
3. ctx_execute 对 /sdcard 的写入不落真实存储（沙箱覆盖层假象：同路径在 ctx_execute 里 du=326K，真实侧 ls 为空）。凡要交付给用户的文件必须用 terminal_exec 写，并在真实侧 ls/du 复核。
4. sdcard 上需 git config core.fileMode false（FUSE 把 755 变 644，6 个 .sh 会一直显示 modified），并对非属主目录加 -c safe.directory='*'。

## 8. 升级到 dsh 0.2.2-alpha.2 可行性（2026-10-29 实测）

npm registry 可达（真实终端 HTTP 200），@deepseek-ai/dsh dist-tags：
alpha=0.2.2-alpha.2 | latest=0.2.1-rc.2 | next=0.2.1-rc.4；0.2.2-alpha.2 共 91 个直接依赖（rc.7 为 61 个）。

实测安装（proot Ubuntu / aarch64 / Node v24，--ignore-scripts）：成功，653 包 / 924 MB / 2 分钟，
落地在 /root/dsh022（保留供后续适配使用）。注意 npm 在此机会 V8 OOM（装 rc.7 时 node::OOMErrorHandler 崩溃，
当时 free 仅剩 4.2G available）—— Termux 上低内存机型需 NODE_OPTIONS=--max-old-space-size 或分步装。

### 8.1 补丁存活情况（patch --dry-run 真实输出）

| 补丁 | rc.6 | 0.2.2-alpha.2 | 原因 |
|---|---|---|---|
| 01-apiproxy-history-slim | OK | **FAIL** | 目标包 dsh-host-apiproxy 已不存在（其 npm latest 停在 0.0.1-rc.1），**永久失效** |
| 02-runtime-incremental-resync | OK | **FAIL** | dsh-client-runtime 包已消失（重构），**永久失效** |
| 03-connection-history-schema | OK | **FAIL** | 包在，文本锚点全变 |
| 04-frontend-static-cache | OK | **FAIL (3/3 hunks)** | 包在，行锚点失效 |
| 05-client-modules-cache | OK | **FAIL (1/1 hunk)** | 包在，行锚点失效 |

仍然有效的部分：
- patches/patch-dsh-android-link.js —— **实测在 0.2.2-alpha.2 上三处全部 [PATCHED]**（session-persistence / attachment-local / fs-local），无需修改。
- apply-frontend.sh 目标 dsh-web-frontend/dist/index.html **仍存在**（注入未实测，目标文件已核实存在）。
- node-pty / koffi / sharp 三个原生依赖仍就位（--ignore-scripts 不编译，依赖需在 Termux 实机验证）。
- 未实测 rc.7 的补丁兼容性（npm OOM 阻断），仅引用仓库自述“最高支持 rc.7 + 补丁基于 rc.6”。

### 8.2 阻断项仍未解

node-addon-require-builtin@0.1.9（2026-10-08 发布，即 0.2.2-alpha.2 要求的 ^0.1.9）的 optionalDependencies
仍只有 darwin / linux-gnu / linux-musl / win32，**无 android**；node-addon-native-custom-loader 内 grep android 无结果。
即 issue #6 的 `No usable native binding found for node-addon-require-builtin-android-arm64` 在 0.2.2-alpha.2 上照样触发。
#6 给出的修法（build.ts 平台白名单 + platform.cc 加 bionic 分支 + 本地编译 .node 到
build/napi/napi-v9-android-arm64/）需在 0.1.9 源码上重新核对锚点，且在手机上编译 C++（估 5-20 分钟）。

### 8.3 升级要改的文件

1. setup.sh：插入 narb 本地编译步骤（幂等 + 失败红字，源码缓存 ~/.cache）；新增 dsh 版本常量与上限校验
2. patches/01、02：重写或删除（目标包已重构掉）；03、04、05：在新版代码上重建差异（先查功能是否已上游内置）
3. README：版本声明从 rc.7 改到 0.2.2-alpha.2，并补 narb 适配说明
4. 未验证设想（风险高）：dsh-app-boot 内仅 1 处引用 narb，且包装脚本已开 --expose-internals，
   可评估用 Node 自带内部模块访问替掉 narb，避开编译。未实测，不可当方案直接用。

## 9. 真机实施结果（2026-10-29，已上 Termux 实机跑通）

设备：onyx / 25053RT47C，Android 15 内核 6.6.118，Termux 0.119.0-beta.3（DEBUGGABLE，故 run-as 可入），无 root。
进入方式：adb(127.0.0.1:5555) -> run-as com.termux（uid u0_a559）。注意 run-as 的 SELinux domain 是 runas_app，
不能读写 /sdcard，也不能读 /data/data/com.termux 以外的路径；日志必须写 Termux 内部再 run-as cat 读出。
工具链：apt 装 nodejs/clang/cmake 后 node/cmake 报 libc++ 符号缺失（_ZNSt6__ndk113__hash_memoryEPKvm），
apt upgrade 全量升级解决。结果：node v26.12.1 / npm 11.21.1 / clang 21.1.8 / cmake 4.4.5 / python 3.14.8。
关键运行参数：process.platform=android, arch=arm64, napi=10, modules=147。

安装：npm i @deepseek-ai/dsh@0.2.2-alpha.2 --ignore-scripts 成 645 包 / 714MB / 56s（npmmirror）。

### 9.1 硬障碍已解（issue #6）
dsh web 复现 fatal：No usable native binding found for node-addon-require-builtin-android-arm64
但 loader 的 attempts 包含 src=local-build —— 本地构建回退真实存在，方案 A 成立。

推翻 issue #6 的一半：
- 它要求给 packages/native/src/{runtime_context,runtime_probe}/platform.cc 加 bionic 分支——**已不需要**，
  上游现在就是 #elif defined(__linux__) && defined(__aarch64__)，不再判 __GLIBC__
- 真需要的只有 scripts/build.ts 的平台白名单（实测在 187 与 251 两处，不只它说的一处）：
  if (process.platform === 'linux')  ->  || process.platform === 'android'
构建细节（issue #6 未提）：
- pnpm 不可用（无 android 二进制），删 packageManager 改用 npm；--ignore-scripts 会跳过 esbuild postinstall，
  需再单独 npm install esbuild 才有 @esbuild/android-arm64，tsx 才能跑
- node file.ts 不行（ESM/CJS 判定失败），node scripts/build.mts 也不行（./path-utils.js 后缀不存在），用 tsx
- 产物落在 napi-v9-linux-arm64-musl/（build.ts 把 bionic 归为 musl），loader 实际找 napi-v9-android-arm64/，
  必须拷贝并重命名——这是最容易漏的一步
自检：bindingSource=local-build，requireBuiltin('internal/modules/esm/loader').getOrInitializeCascadedLoader 为 function
dsh web 实测：监听成功、未带 token 访根路径 401、带 token 访根路径 303

### 9.2 本轮新发现的 bug（已修，建议回馈上游）
dsh-session-persistence-jsonl/lib/index.js 有两类旧 link 脚本盖不到的引用：
A) 第 1615 行对象字面量里的简写属性 link,（defaultFileSystem）——脚本从 import 删了 link，
   但只改 `await link(tmp, finalPath)` 调用点，简写属性被漏下→模块 import 即 ReferenceError: link is not defined，
   dsh 侧表现为 session-persistence-jsonl: failed to import（会话不能持久化，不报错到 UI）
   —— 本质就是 issue #7 说的“半修好”，只是发生在这个包
B) dsh-attachment-local/lib/index.js:494 await link(source, target) 与 :555 await link(staged.path, target)——
   参数名与脚本锚点 await link(temporary, target) 不一致，完全没被改，Android 上照旧 EACCES
修在 v2/patches/15-link-residue.mjs：A 类展开为 link: (a,b) => rename(a,b)（保留属性名），
B 类改 rename；**只新增绝不从 import 删 link**（多余导入无害，缺导入致命）。实测修后三包 IMPORT_OK、
failed to import 仍计数 0、带 token 访根路径仍 303、重跑幂等（本次修补 0 个文件）。

### 9.3 v2 框架实测行为
$ node v2/dsh-patch.mjs --root <...>/node_modules/@deepseek-ai --check
[skip] 10-android-link   link->rename
[skip] 15-link-residue   0.2.x link 残余清算
[skip] 20-narb-android   binding 已可用（local-build）
[n/a]  30-static-cache-immutable  锚点在 frontend-static:82，但 dist 无内容哈希资产，改 immutable 会缓存过期
[n/a]  40-subprocess-android      4 处 platform==="linux"（index.js:1037,1586; runner-launch:670,811）未盲改
退出码 2 = 有待人工重建的锚点（区别于真失败 1）。补丁不再靠行号：失配只报告不写盘。
两个未启用项是故意保留的：30 需要上游确认，40 影响沙箱判定，改错了会让 bash 工具直接失效。

## 10. 接 AMD Radeon 端点（2026-10-29，已配置并验证）

端点 https://developer.amd.com.cn/radeon/api/v1（密钥只进设备凭据库，未进仓库/日志，grep 复核 key_hits=0）：
- 未带鉴权 /models = 401，根路径 200；带密钥 /models = 200，15 个模型，其中 10 个 tools+streaming 可用
- Bearer 与 x-api-key 两种头都接受；协议是 OpenAI chat/completions（dsh 侧名 openai-completions）
- 真调用 DeepSeek-V4.1-Flash 返回 "PONG"（1.16s），stream:true 返回 200 + SSE 分片
- 404 body 是 {"detail":{"error":{"code":"model_not_found"}}}，可区分“路径错”与“模型名错”

配置三处（缺一不可）：
1. ~/.dsh/.credentials.yaml 加 refs.AMD_RADEON_KEY（0600，必须保留原有 records 段——那是浏览器会话密钥）
2. profiles/web/cordis.patch.yml 加 llm-pi-ai.config.providers.radeon（api/baseURL/apiKeyEnv/models）
3. sandbox-policy.mode: danger-full-access 必须同时配 permission.defaultPreset: danger-full-access
   实测：只改 sandbox 时启动有 1 个入口不激活（permission: composed sandbox and approval defaults
   match no preset，沙箱放开后派生成 custom）；补 defaultPreset 后 entry_inactive 从 1 变 0。

验证结果：--dump-config 里 radeon 六个模型完整出现；启动 import_fail=0 entry_inactive=0；
带 token 访根路径 303；脚本读回配置得 api=openai-completions models=6 keyRef=AMD_RADEON_KEY。

未验证（如实说明）：dsh web profile 无 one-shot 跑 prompt 入口，模型列表走 WebSocket RPC 而非 REST，
所以“在 dsh 对话里真的用这个模型跑一轮”尚未证明——只证明了 provider 已注册、密钥可解析、端点可用。
模型选择是运行时状态（存浏览器会话记录，不在 profile），需在 Web UI 的 Models 页手动选一次。
模板与 runbook：v2/profile/cordis.patch.amd-radeon.yml、v2/README-provider.md（提交 8d1526b）。

## 11. 补移动端前端适配到 0.2.2（2026-10-29）

发现缺口：检查真机 dist/index.html 发现 dsh-mobile-adapt=0、AbortSignal polyfill=0 ——
早期 apply-frontend.sh 默认路径指向全局 npm 布局（/usr/lib/node_modules/...），rc.7 时代跑在
proot 副本上，从未命中 Termux 真安装，所以移动端 CSS 与 polyfill 对这台设备一直没生效。

处置：新增 v2/apply-frontend-022.sh（只改 HTML 路径默认值为 $HOME/dsh022/...，复用原
apply-frontend.sh 的幂等注入逻辑，支持 TERMUX_HOME 覆盖）。

实测：index.html 1009 → 21987 字节；重跑输出「无改动」证明幂等；备份 index.html.bak。
重启服务后从设备侧带 cookie 抓真实响应：59623 字节（未注入时 38645），
其中 dsh-mobile-adapt=2、AbortSignal.any=4、viewport-fit=1、interactive-widget=2 ——
证实 dsh-host-frontend-static 启动时读 dist/index.html 再注入 boot 样式，改文件确实生效。

顺带确认：0.2.2 上游 manifest.webmanifest 已是 "display": "standalone"，脚本那步自动 skip，
rc.7 时代的 fullscreen→standalone 修补在新版不再需要。

仍未验证：浏览器里的真机渲染（键盘是否跟随、tooltip 是否重吸附）需人在屏前确认，
脚本只能证明文件与服务端响应已含注入内容，不能替代肉眼验收。

## 12. 0.2.2 在 Android 上 flock 崩溃（2026-10-30）

症状：浏览器打开会话报 `flock is not supported on android-arm64`。

根因（三层叠加，缺一不炸）：
1. `@deepseek-ai/node-addon-system/lib/flock.js` 的 `loadBinding()` 平台门只允许
   `linux|darwin`，而 Termux 的 Node 把 `process.platform` 报成 `android`，直接 throw
   `ERR_FLOCK_UNSUPPORTED_PLATFORM`。
2. 上游 `optionalDependencies` 只发 darwin/linux 的 addon；`npm view
   @deepseek-ai/node-addon-system-android-arm64` 返回 404 —— 没有任何可用的 android 原生实现，
   所以装包解决不了，只能改代码。
3. 调用方 `dsh-session-persistence-jsonl` 的 `isLockContention()` 只认 EAGAIN/EWOULDBLOCK，
   不支持平台的错误码一路向上抛，`session.lock` 拿不到 → 会话完全打不开。

处置：`v2/apply-flock-android.sh` 在 `tryLockExclusive` 开头加 android 早退（等价 rc.7 无锁行为）。
代价：失去跨进程互斥；dsh 本机单进程服务，实际不受影响。备份 `flock.js.rc7bak`。

验证：脚本内置自测输出 `LOCK_OK`；重启服务后 `dsh headless` 不再报 flock
（`flock_hits=0`），改为 `MISSING_CREDENTIAL: deepseek-official` —— 证明已过锁阶段，
下一关是默认 profile 走官方路由而非 AMD。

顺带踩到两个 v2 脚本通用坑（已修）：
- `run-as` 下 `$HOME` 是 `/data/user/0/com.termux`，没有 dsh022；HOME 必须从 `$PREFIX/..` 推导
  或用 `TERMUX_HOME` 覆盖，不能信环境里的 HOME。
- `run-as` 下 bash 往 `/data/local` 写临时文件会 `Permission denied`，必须 `export TMPDIR=$PREFIX/tmp`。

## 13. AMD Radeon 端到端跑通（2026-10-30）

结果：dsh 0.2.2 在 Android/Termux 上真用 AMD Radeon 端点完成一轮对话。
一手证据（非人肉口述）：`storages/session_projcache/sessions/<id>.json` 里
`record.rows.modelSelection.val.lastUsed = {provider: "radeon", model: "Qwen3.8-27B"}`，
会话正文写入 `sessions/<proj>/<sid>/session.v4.jsonl.zstd`（59 KB，zstd 压缩存储）。

模型列表为空的真因（与 flock 无关，是我自己埋的一行 bug）：
`start_web.sh` 里 `. $HOME/.amd_env` 被写在 `export HOME=...` **之前**。run-as 环境下
`$HOME=/data/user/0/com.termux`，那里没有 .amd_env，source 静默失败 → 服务进程环境里
从来没有 `AMD_RADEON_KEY` → `apiKeyEnv` 解析不到 key → provider 不可用 → Models 页空白。
修法：source 移到 `export HOME=` 之后并改绝对路径；重启输出 `amd_key_set=yes` 确认生效。

教训（通用，两个 v2 脚本都踩过）：在 run-as 下任何依赖 `$HOME` 的行，都必须排在显式
`export HOME=` 之后；source 一个不存在的文件不报错，所以这类 bug 只会以“功能静默缺失”暴露。

遗留：flock 补丁与前端适配都打在 node_modules 内，`npm i` 重装会丢；重投方式：
`apply-flock-android.sh` + `apply-frontend-022.sh`（已幂等）。凭据 store 的 refs 未建 records
条目（目前靠环境变量旁路），若要回到 dsh 原生存法需继续查 dsh-credentials 的 record 格式。

## 14. FUSE 的 .l2s.tmp_* 承载 git 对象，不可删（2026-10-30 自伤实录）

/sdcard 上 .git/objects/??/.l2s.tmp_obj_* 不是垃圾——是 FUSE 层物化 loose object 的载体。
我当垃圾删了，fsck 立刻报 object corrupt/missing、HEAD bad object；稍后 FUSE 重新物化才恢复。
规则：① .l2s.tmp_* 一律不碰；② git 操作放 ext4（$HOME/rN）做，只同步最终内容；
③ 跨 ext4/sdcard 传仓库优先 git bundle 或 tar 时 --exclude='.l2s*'，避免把载体拷成断链。
