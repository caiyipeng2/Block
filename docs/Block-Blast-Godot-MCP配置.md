# Block Godot MCP 与美术工具配置

更新：2026-10-16。项目使用 Godot 4.7.2。本页记录本机开发工具的安装位置、连接方式和恢复方法，供后续 Codex 会话与人工维护使用。

## 当前状态与验收边界

| 组件 | 已完成 | 尚需确认 |
| --- | --- | --- |
| Godot AI 4.3.0 | 官方签名发布包已验签、核对完整清单并安装；无界面导入检查通过；客户端自动迁移完成；按实际 Codex 配置握手通过，列出 47 个工具；临时无界面编辑器的 Block 会话与双向认证连接已核验 | 用户正常重开 Godot、刷新 Codex MCP 以加载新配置；界面、操作与声音由用户验收 |
| Tripo CLI 0.7.0 | CLI 与 stdio MCP 已安装；初始化、工具枚举与 ping 通过，列出 5 个工具；阿里云 Token Plan LLM 辅助配置已保存并完成一次小请求验证 | 尚无 Tripo 3D API Key；3D API 认证、余额及生成未通过验收 |
| Sprite Pipeline | 沿用已安装的 OpenAI `game-studio:sprite-pipeline` skill；Python/Pillow 后处理环境检查通过 | 本轮未生成或导入新精灵图，未做引擎内动画验收 |

Godot `--headless --editor --import` 退出码为 `0`，未发现 SCRIPT、Parse 或 Compile 错误。这是导入与脚本检查证据。Godot AI 默认在 headless 模式下禁用，因此该检查本身不代表 MCP 已连接。随后另用显式允许插件运行的临时无界面编辑器，确认了真实插件会话、认证与双向连接；该检查没有运行游戏。

本轮不运行游戏场景、GUI 点击/拖动、声音验收或完整自动测试，也未创建 Tripo 3D 生成任务或图片生成任务。实际界面、操作与声音继续由用户在 Godot 中验收。

## 组件与本机位置

| 项目 | 位置或版本 |
| --- | --- |
| 项目目录 | `E:\FunBlock Studio\block` |
| Codex 全局配置 | `E:\CodexHome\config.toml` |
| Godot AI 插件 | `E:\FunBlock Studio\block\addons\godot_ai` |
| Godot AI 许可证副本 | `E:\FunBlock Studio\block\godot-ai-LICENSE.txt` |
| Godot AI uv 缓存 | `E:\Tools\GodotAI\uv-cache` |
| uvx 执行器 | `C:\Users\EDY\.local\bin\uvx.exe` |
| Godot AI 无窗口 Python 启动器 | `C:\Users\EDY\AppData\Roaming\uv\python\cpython-3.12-windows-x86_64-none\pythonw.exe`；uv 管理的 CPython 3.12，仅包装 uvx |
| Tripo CLI | `E:\Tools\TripoAI\cli-0.7.0\node_modules\tripo-cli\dist\cli.js` |
| Tripo 私有配置与历史 | `E:\Tools\TripoAI\profile`，通过 `TRIPO_HOME` 指定；LLM 配置位于其中的 `config.json`，不提交 |
| Node.js | `C:\Program Files\nodejs\node.exe`，本机 26.4.0；Tripo 依赖的 commander 15 实际要求 Node.js ≥22.12.0 |
| Sprite Pipeline skill | `E:\CodexHome\plugins\cache\openai-api-curated\game-studio\0722921d\skills\sprite-pipeline\SKILL.md` |

Tripo 顶层包的 `engines` 标注 Node.js ≥20，但其已安装依赖要求更高；重装时按 ≥22.12.0 准备运行时。本机 Node.js 满足要求。以上含本机绝对路径，迁移电脑时应更新对应配置，不能直接复制后认定可用。

## Godot AI：连接 Codex 与编辑器

### 来源与安装内容

本项目使用作者 **dlight** 的 [Godot AI，AssetLib #5050](https://godotengine.org/asset-library/asset/5050)，官方仓库为 [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)。其用途是向外部 MCP 客户端开放 Godot 编辑器操作，许可证为 MIT。

不要与作者 mpxxv 的同名 [AssetLib #5067](https://godotengine.org/asset-library/asset/5067) 混淆；后者是编辑器内聊天助手。

项目最初从 AssetLib 安装 3.2.1；用户点击 Update 后进入 **Godot AI v4 Migration 4.3.0** 临时迁移桥。该名称表示迁移胶囊，不能当作正式 v4 安装成功的证据。目前已经关闭编辑器并使用官方安装器恢复为 **Godot AI 4.3.0**，要求 Godot 4.7+，没有修改供应商插件源码。

- 发布页：[Godot AI v4.3.0](https://github.com/hi-godot/godot-ai/releases/tag/v4.3.0)。
- 发布源提交：`b82b5c519b1b17228f70d8effce1626f391bd1dd`。
- 正式安装包：`godot-ai-v4-plugin.zip`；本次使用用户已下载迁移桥内 `migration_payload` 携带的正式 ZIP、manifest 和 signature。
- 正式 ZIP SHA256：`dbc3d16e1aa7a5f3ae8038a150bf4191162112f4329c79611aa6f656e3ca4e58`。
- 已用固定发布提交的官方 `script/v4-release` 完成 RSA 签名、发布身份、ZIP 哈希和完整文件清单验证，并在安装后再次验证完整目录；单独比对 SHA256 不能替代签名验证。
- 固定版本说明：[v4.3.0 更新机制](https://github.com/hi-godot/godot-ai/blob/v4.3.0/docs/self-update.md)、[官方恢复接口](https://github.com/hi-godot/godot-ai/blob/v4.3.0/docs/releasing.md#recovery-the-three-marker-states)。

`project.godot` 已有以下启用项：

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
```

重新打开项目后，Godot 的“项目 → 项目设置 → 插件”应显示 Godot AI 已启用，编辑器中应出现 Godot AI dock。若列表缺失，先确认 `addons/godot_ai/plugin.cfg` 存在，避免多套一层目录或错误放成 `addons/plugin.cfg`。

### Codex 连接方式

全局配置新增的 MCP 名称为 `godot-ai`。连接链路为：

```text
Codex → godot-ai attach（stdio）→ 认证后的 Python 服务（本机 HTTP 8001）
      → Godot AI 插件（本机 WebSocket 8002）→ 已打开的 Godot 项目
```

服务固定为 `godot-ai==4.3.0`，通过 uvx 启动，环境变量 `UV_CACHE_DIR` 指向 `E:\Tools\GodotAI\uv-cache`。Windows 使用 `pythonw.exe` 包装 uvx，保留 MCP 标准输入输出管道并隐藏子进程控制台。配置等待时间为 `startup_timeout_sec = 60`、`tool_timeout_sec = 360`。v4 迁移已保存独立端口对 HTTP 8001 / WebSocket 8002，旧 8000 / 9500 不再用于此项目的 v4 连接。

核心服务参数如下，仅用于核对；实际执行器绝对路径以本机 Codex 配置为准：

```text
uvx --isolated --no-config --no-env-file --no-sources --no-build --index-strategy first-index --keyring-provider disabled --index https://pypi.org/simple --default-index https://pypi.org/simple --find-links https://pypi.org/simple/godot-ai/ --link-mode copy --from godot-ai==4.3.0 godot-ai attach --port 8001 --ws-port 8002 --disable-telemetry
```

维护时保留官方隔离、固定官方索引、禁用构建等 uvx 参数，以及固定版本与 Windows 无窗口包装。v3 与 v4 不能互通；不要仅升级 Python 服务或仅修改插件版本。[官方客户端配置说明](https://github.com/hi-godot/godot-ai/blob/v4.3.0/docs/client-configuration.md)

若需要重建丢失的 `godot-ai` 配置，可用以下无凭据骨架。仅合并该 MCP 段，保留配置中的其他服务器和现有环境选项；迁移后先更新绝对路径。

```toml
[mcp_servers."godot-ai"]
command = 'C:\Users\EDY\AppData\Roaming\uv\python\cpython-3.12-windows-x86_64-none\pythonw.exe'
args = [
  '-c',
  'import subprocess,sys; raise SystemExit(subprocess.call(sys.argv[1:], stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr, creationflags=0x08000000))',
  'C:\Users\EDY\.local\bin\uvx.exe',
  '--isolated', '--no-config', '--no-env-file', '--no-sources', '--no-build',
  '--index-strategy', 'first-index', '--keyring-provider', 'disabled',
  '--index', 'https://pypi.org/simple',
  '--default-index', 'https://pypi.org/simple',
  '--find-links', 'https://pypi.org/simple/godot-ai/',
  '--link-mode', 'copy', '--from', 'godot-ai==4.3.0',
  'godot-ai', 'attach', '--port', '8001', '--ws-port', '8002',
  '--disable-telemetry',
]
enabled = true
startup_timeout_sec = 60
tool_timeout_sec = 360

[mcp_servers."godot-ai".env]
UV_CACHE_DIR = 'E:\Tools\GodotAI\uv-cache'
GODOT_AI_DISABLE_TELEMETRY = '1'
```

### 开始使用与连接排查

1. 本次临时无界面编辑器已验证真实 Block 会话，检查进程由维护过程收尾退出。用户继续工作时正常打开 `E:\FunBlock Studio\block\project.godot`，插件名称应为正式 Godot AI 4.3.0，并检查 Godot AI dock 的连接状态。临时 `Godot AI v4 Migration` 名称不能代表迁移完成。
2. 重启 Codex 中对应的 MCP 服务；若当前客户端没有重新加载入口，则重启 Codex，再开新一轮会话加载工具。安装后尚未刷新的当前工具列表不能用于判断配置是否存在。
3. 先做只读确认，例如列出编辑器会话、读取当前项目路径或场景树。确认目标是 Block 项目后，再使用会修改编辑器的工具。
4. 若启动超时，检查 Python/uvx 路径、固定版本缓存和两个端口。端口已占用或被 Windows 保留时，在 Godot AI 的编辑器设置中调整端口，再同步 Codex attach 参数。
5. 只有 MCP 工具目录可见，尚不能证明某个 Godot 编辑器项目在线。应同时核对编辑器会话与项目路径。

Godot AI 默认跳过 headless 启动；`GODOT_AI_ALLOW_HEADLESS` 是刻意运行 CI/编辑器测试时的显式开启入口，普通语法/导入检查无需设置。不要为了重复检查而启动 GUI 或执行游戏自动验收。[headless 行为说明](https://github.com/hi-godot/godot-ai/blob/v4.3.0/docs/server-lifecycle.md#headless-and-unsupported-editors)

### 更新与导出

v4 使用带认证的 stdio attach，不能使用裸 HTTP MCP URL 代替。后续更新遵循 [固定版本更新机制](https://github.com/hi-godot/godot-ai/blob/v4.3.0/docs/self-update.md)，同时处理插件与客户端配置，不把新目录直接覆盖到已加载的旧插件。

2026-10-16 的迁移中断已定位并验证：CodeGraph MCP 的目录 watcher 持有 `addons/godot_ai` 下 296 个目录句柄。用户关闭 Godot 后，官方离线安装仍在重命名旧插件目录时返回 `WinError 5`；停止该 watcher 后，同一官方安装命令立即成功。因此本机 CodeGraph MCP 参数已新增 `--no-watch`，后续每个任务仍主动运行 `codegraph sync`，避免 watcher 再次阻止插件完整目录替换。无需为此禁用签名验证或降低 TLS 检查。

失败现场压缩包保留在 `work/mcp-update-investigation/backup`，不提交。完整旧迁移桥保留在 `addons/.godot_ai_update/backup/3.2.1`。离线安装器起初读取桥的 `plugin.cfg`，将来源版本记为 4.3.0；恢复时依据原激活记录核对并修正为真实来源 3.2.1 和对应 backup 路径。当前 `pending.json` 为 `status: success`、`clients_migrated: true`。这些是本次恢复记录，后续不要照抄手工改 marker；应先保留错误和备份，再使用官方恢复接口。

`export_presets.cfg` 已将 `addons/godot_ai/*` 和 `godot-ai-LICENSE.txt` 加入开发工具排除项。该设置尚未通过本轮实际导出包验证；本轮没有重新导出 Windows 游戏。

## Tripo：3D 生成 MCP 与本机登录

本机安装的是 [Tripo 官方文档](https://developers.tripo3d.ai/en/docs/cli) 指定的 npm 包 [`tripo-cli@0.7.0`](https://www.npmjs.com/package/tripo-cli/v/0.7.0)，由 `node.exe` 执行 `dist/cli.js mcp` 提供 stdio MCP。它处理 3D 资产，与 Godot AI 的编辑器连接职责不同。

Codex 全局 MCP 名称为 `tripo`，配置包含：

- 启动参数：`E:\Tools\TripoAI\cli-0.7.0\node_modules\tripo-cli\dist\cli.js mcp`。
- `TRIPO_HOME = E:\Tools\TripoAI\profile`，将配置、账号 profile 和历史留在项目外。
- `TRIPO_ANALYTICS_ENABLED = 0`，关闭 CLI 匿名用量分析。
- `env_vars = ["TRIPO_API_KEY", "TRIPO_REGION"]`，允许从 Codex 启动环境继承 Key 和账号区域。该字段只声明继承变量名，不保存 Key 值；已继承的 `TRIPO_API_KEY` 会优先于本机账号 profile。

Tripo CLI 的 **LLM 辅助凭证**与 **Tripo 3D API 凭证**是两个独立配置。本机已按用户提供的信息配置 LLM 辅助：

- 私有位置：`E:\Tools\TripoAI\profile\config.json` 的 `llm.api_key`，文件权限已限制；Key 不写入项目文档、脚本或版本库。
- `base_url`：`https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`。
- 模型：从实时 `models list` 返回目录选择 `qwen3.7-plus`；`auto` 不接受 CLI 当前固定传入的 `temperature`，因此没有使用该路由。
- 已完成一次最多 16 输出 token 的小请求，HTTP 成功；Tripo `resolveLlmConfig` 解析到的配置与之相符。

上述 Key 用于 CLI 的 LLM 辅助，不是 Tripo 3D 生成凭证。当前尚无 Tripo 控制台签发的 3D API Key，3D API 认证未通过；曾用于核对的非 3D Key 没有存入 Tripo 3D 登录 profile。LLM 请求成功不能当作 3D 认证、余额或生成通过。

以后取得 Tripo 3D API Key 后，在本机交互式 PowerShell 运行现有脚本：

```powershell
powershell -ExecutionPolicy Bypass -File "E:\FunBlock Studio\block\tools\configure_tripo.ps1"
```

脚本保留用于将来录入 Tripo 3D API Key：调用官方 `login --paste`，以密码输入方式读取 Key，保存到与 Codex MCP 相同的 `E:\Tools\TripoAI\profile`。`--paste` 需要交互终端，不要让无交互的 MCP 调用代替输入。可按账号需要追加 `-Region cn` 或 `-Region ov`；不要把 Key 放进命令参数、聊天、文档或版本库，也不要将阿里云 LLM Key 填到这里。

本版 CLI 不使用 `tripo config set api_key` 完成登录。若改用 `TRIPO_API_KEY` 环境变量，应同时核对 `TRIPO_REGION`（国内站 `cn`、国际站 `ov`），并重新启动 Codex，使 MCP 子进程继承更新后的环境；未配置区域且无登录 profile 时默认为 `ov`。如果 Key 环境变量仍有旧值，它会覆盖刚保存的 profile。按脚本登录会自动验证并保存账号区域。

登录后的只读诊断可在 PowerShell 执行；这一步会联系 Tripo 检查认证、网络与余额，不创建生成任务：

```powershell
$env:TRIPO_HOME = 'E:\Tools\TripoAI\profile'
$env:TRIPO_ANALYTICS_ENABLED = '0'
node.exe 'E:\Tools\TripoAI\cli-0.7.0\node_modules\tripo-cli\dist\cli.js' doctor
```

MCP 握手或工具目录可见不等于账号认证通过。登录与诊断完成后，仍应在明确需要资产生成时再提交生成任务；安装和握手本身没有证明任何模型已生成。

## Sprite Pipeline：沿用 OpenAI skill

用户已确认继续使用已安装的 `game-studio:sprite-pipeline`。它是一套 2D 精灵动画工作流，**没有另建独立的 Sprite Pipeline MCP 服务**，也没有新增一个待配置的精灵服务 Key。官方来源见 [Sprite Pipeline skill](https://github.com/openai/plugins/blob/main/plugins/game-studio/skills/sprite-pipeline/SKILL.md) 与 [game-studio 插件清单](https://github.com/openai/plugins/blob/main/plugins/game-studio/.codex-plugin/plugin.json)。

工作流从用户认可的首帧开始，一次生成完整动画条带，再通过 Python/Pillow 脚本统一缩放、帧尺寸与锚点，输出帧图和预览图。后处理环境为 `C:\Python314\python.exe` 3.14.3、Pillow 12.2.0；三个脚本 `build_sprite_edit_canvas.py`、`normalize_sprite_strip.py`、`render_sprite_preview_sheet.py` 的 `--help` 均退出 `0`。

实际图片生成沿用 OpenAI imagegen 能力；本轮只检查已有 skill 与后处理依赖，没有发起生成。对应 skill 位于上方本机位置表，后续插件升级可能改变缓存目录。

## 关闭、恢复与迁移

- 临时关闭某个 MCP：在 `E:\CodexHome\config.toml` 中仅将对应 `godot-ai` 或 `tripo` 的 `enabled` 设为 `false`，再重启对应服务或 Codex。保留原有 CodeGraph、OpenAI 文档及其他配置。
- 关闭 Godot 插件：在 Godot“项目设置 → 插件”中禁用 Godot AI。若从文件恢复，只移除 `editor_plugins/enabled` 数组中该插件路径，保留其他插件。Godot AI 启用时可能登记 `_mcp_game_helper` autoload，正常禁用会移除它；手工撤回时应核对该项。
- 恢复 Godot AI 安装：关闭项目，保留更新目录与完整错误，使用相应正式发布版本的官方 `script/v4-release install` 对 canonical ZIP、manifest、signature 做验签与完整目录替换。若 rename 被拒绝，先核对打开的目录句柄及其持有进程，不能仅凭端口或旧 PID 猜测并终止进程。配置或端口变化后同步 attach 参数；不要只替换部分供应商脚本，也不要直接解压覆盖。
- 更换 Tripo 账号：在同一个 `TRIPO_HOME` 下重新登录或使用 CLI 的 profile 管理；需要退出时使用官方 `logout`。若设置了 `TRIPO_API_KEY`，同时核对其优先级，避免仍使用旧账号。
- 迁移电脑：重新准备 uv/Python、Node 和固定版本工具，再更新绝对路径并重新登录。缓存、日志、个人 profile、凭据以及全局配置备份均留在本机，不提交项目仓库；不复制包含 Key 的配置全文到交付记录。

## 核验记录

- Godot AI 安装：4.3.0 正式包验签、发布身份、ZIP 与完整文件清单校验通过；官方安装成功，保留旧树；`pending.json` 为 `success` 且 `clients_migrated: true`。Godot 4.7.2 无界面编辑器导入退出码 `0`，无 SCRIPT/Parse/Compile 错误。
- Godot AI 配置与握手：官方客户端自动迁移完成；Codex `godot-ai` 已固定 4.3.0，端口为 8001 / 8002，保留官方安全参数、无窗口包装与 E 盘缓存。按实际 Codex 配置握手通过，列出 47 个工具。
- Godot 编辑器连接：临时无界面编辑器的只读 `session_manage`（`op: list`）返回 `count: 1`，项目为 `E:/FunBlock Studio/block/`，`plugin_version` 与 `server_version` 均为 `4.3.0`，`protocol_version: 2`、`readiness: ready`、`play_state: stopped`；编辑器日志确认 `authenticated with server`。实际插件与后端双向连接已验证；没有运行游戏，不以旧 3.2.1 的 46 工具或空会话结果作为 v4 证据。
- CodeGraph：持有插件目录句柄的 watcher 是本次 rename 失败的已验证原因；MCP 新增 `--no-watch`，每任务主动 `codegraph sync`。
- Tripo：CLI 0.7.0 的 MCP 初始化、`tools/list` 与 `ping` 通过，列出 5 个工具；LLM 辅助小请求 HTTP 成功且配置解析一致。尚无有效 Tripo 3D API Key，未通过 3D 认证、余额或生成验收，未创建 3D 任务。
- Sprite Pipeline：Python/Pillow 后处理环境检查通过；`configure_tripo.ps1` 已通过 PowerShell 解析检查并保留供将来录入 Tripo 3D API Key。
- 后续使用：用户正常重开 Godot 项目并刷新 Codex MCP，使日常会话加载新配置；将来取得 Tripo 3D Key 后再登录与诊断。资产生成及游戏界面、操作、声音验收均未执行。
