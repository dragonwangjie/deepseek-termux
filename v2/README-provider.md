# 接自定义 OpenAI 兼容端点（以 AMD Radeon 本地推理为例）

实测环境：Termux / dsh 0.2.2-alpha.2 / 2026-10-29。

## 1. 探端点（先别写配置）
```sh
K=你的key
B=https://developer.amd.com.cn/radeon/api/v1
curl -s -H "authorization: Bearer $K" "$B/models" | head -c 400
curl -s -H "authorization: Bearer $K" -H 'content-type: application/json' \
  -d '{"model":"DeepSeek-V4.1-Flash","max_tokens":16,"messages":[{"role":"user","content":"Reply: PONG"}]}' \
  "$B/chat/completions"
```
要点：`/models` 返回 200 且能列 id 才算可用；`404 model_not_found` 说明路径对、模型名错。
该端点 `Bearer` 与 `x-api-key` 都接受，协议为 OpenAI `chat/completions`（dsh 里叫 `openai-completions`）。

## 2. 存密钥（走 dsh 自己的凭据库，不进 shell 配置）
文件 `$DSH_HOME/.credentials.yaml`（默认 `~/.dsh/.credentials.yaml`），权限必须 0600：
```yaml
version: 1
refs:
  AMD_RADEON_KEY: rc-xxxx
```
注意保留原有 `records:` 段（dsh 的浏览器会话密钥在那）。键名规则 `/^[A-Za-z_][A-Za-z0-9_]*$/`。

## 3. 注册 provider（profile 层 cordis.patch.yml）
见 `v2/profile/cordis.patch.amd-radeon.yml`。三条缺一不可：
- `llm-pi-ai.config.providers.<route>`：`api` 必须是 `openai-completions` / `openai-responses` / `anthropic-messages` 之一
- `apiKeyEnv` 指向上面的 ref 名（不是密钥本身）
- Android 还需 `sandbox-policy.mode: danger-full-access`，**并配 `permission.defaultPreset: danger-full-access`**
  —— 沙箱放开后派生出 `custom`，不显式指定会让 permission 入口不激活（启动时 `did not activate` 告警）

## 4. 验证
```sh
node <dsh>/lib/bin.js --profile web --dump-config | grep -A14 'id: llm-pi-ai'
node <dsh>/lib/bin.js web --port 3093 --host 127.0.0.1 --no-open &
# 看启动日志：failed to import 计数 0、did not activate 计数 0
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:3093/?token=<日志里的 token>"   # 期望 303
```
实测输出：`config: api=openai-completions models=6 keyRef=AMD_RADEON_KEY`、`import_fail=0`、`entry_inactive=0`、`with_token=303`。

模型选择是运行时状态（存浏览器会话记录，不在 profile），所以在 Web UI 的 Models 页选中 `AMD Radeon` 下任一模型即可；
`--dump-config` 能列出 provider 就说明路由已注册。
