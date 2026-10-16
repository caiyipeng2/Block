# Block Godot MCP 与美术工具配置

更新：2026-10-16。项目使用 Godot 4.7.2。本页记录本机开发工具的安装位置、连接方式和恢复方法，供后续 Codex 会话与人工维护使用。

## 当前状态与验收边界

| 组件 | 已完成 | 尚需确认 |
| --- | --- | --- |
| Godot AI 3.2.1 | AssetLib 原始包已安装；项目已声明启用；Godot 无界面导入检查通过；固定版本服务已预热；MCP 初始化、工具枚举与 ping 通过，列出 46 个工具；只读查询成功且当前会话数为 0 | 当前旧编辑器尚未装载插件，须由用户保存后重新打开项目，再确认项目会话 |
| Tripo CLI 0.7.0 | 官方 CLI 已安装；stdio MCP 初始化、工具枚举与 ping 通过，列出 5 个工具；本机填写 Key 的脚本已提供 | 用户稍后在本机完成登录；认证、余额及生成均未验收 |
| Sprite Pipeline | 沿用已安装的 OpenAI `game-studio:sprite-pipeline` skill；Python/Pillow 后处理环境检查通过 | 本轮未生成或导入新精灵图，未做引擎内动画验收 |

Godot `--headless --editor --import` 退出码为 `0`，未发现 SCRIPT、Parse 或 Compile 错误。这是导入与脚本检查证据。Godot AI 默认在 headless 模式下禁用，因此该检查不代表 Codex 已连接到正在运行的编辑器。

本轮不运行游戏场景、GUI 点击/拖动、声音验收或完整自动测试，也未调用 Tripo 或图片生成。实际界面、操作与声音继续由用户在 Godot 中验收。

## 组件与本机位置

| 项目 | 位置或版本 |
| --- | --- |
| 项目目录 | `E:\FunBlock Studio\block` |
| Codex 全局配置 | `E:\CodexHome\config.toml` |
| Godot AI 插件 | `E:\FunBlock Studio\block\addons\godot_ai` |
| Godot AI 许可证副本 | `E:\FunBlock Studio\block\godot-ai-LICENSE.txt` |
| Godot AI uv 缓存 | `E:\Tools\GodotAI\uv-cache` |
| uvx 执行器 | `C:\Users\EDY\.local\bin\uvx.exe` |
| Godot AI Python | `C:\Users\EDY\AppData\Roaming\uv\python\cpython-3.12.13-windows-x86_64-none\python.exe`，版本 3.12.13 |
| 无窗口 Python 启动器 | `C:\Python314\pythonw.exe`；它仅包装 uvx，服务仍由上面的 Python 3.12 运行 |
| Tripo CLI | `E:\Tools\TripoAI\cli-0.7.0\node_modules\tripo-cli\dist\cli.js` |
| Tripo 私有配置与历史 | `E:\Tools\TripoAI\profile`，通过 `TRIPO_HOME` 指定 |
| Node.js | `C:\Program Files\nodejs\node.exe`，本机 26.4.0；Tripo 依赖的 commander 15 实际要求 Node.js ≥22.12.0 |
| Sprite Pipeline skill | `E:\CodexHome\plugins\cache\openai-api-curated\game-studio\0722921d\skills\sprite-pipeline\SKILL.md` |

Tripo 顶层包的 `engines` 标注 Node.js ≥20，但其已安装依赖要求更高；重装时按 ≥22.12.0 准备运行时。本机 Node.js 满足要求。以上含本机绝对路径，迁移电脑时应更新对应配置，不能直接复制后认定可用。

## Godot AI：连接 Codex 与编辑器

### 来源与安装内容

本项目使用作者 **dlight** 的 [Godot AI，AssetLib #5050](https://godotengine.org/asset-library/asset/5050)，官方仓库为 [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)。其用途是向外部 MCP 客户端开放 Godot 编辑器操作，许可证为 MIT。

不要与作者 mpxxv 的同名 [AssetLib #5067](https://godotengine.org/asset-library/asset/5067) 混淆；后者是编辑器内聊天助手。

本次按 AssetLib 发布版本安装 **3.2.1**，支持 Godot 4.5+。发布包原样提取至 `addons/godot_ai`，没有修改供应商插件源码。

- 下载地址：[v3.2.1 / godot-ai-plugin.zip](https://github.com/hi-godot/godot-ai/releases/download/v3.2.1/godot-ai-plugin.zip)
- SHA256：`ecf882058f5e5ab691cc5ad6f3c3853b8d57a88f6ed90c068c5e492fea5e3b2b`
- 校验来源：[官方发布附件](https://github.com/hi-godot/godot-ai/releases/expanded_assets/v3.2.1)
- 固定版本说明：[v3.2.1 README](https://github.com/hi-godot/godot-ai/blob/v3.2.1/README.md)

`project.godot` 已有以下启用项：

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
```

重新打开项目后，Godot 的“项目 → 项目设置 → 插件”应显示 Godot AI 已启用，编辑器中应出现 Godot AI dock。若列表缺失，先确认 `addons/godot_ai/plugin.cfg` 存在，避免多套一层目录或错误放成 `addons/plugin.cfg`。

### Codex 连接方式

全局配置新增的 MCP 名称为 `godot-ai`。连接链路为：

```text
Codex → godot-ai attach（stdio）→ Python 服务（本机 HTTP 8000）
      → Godot AI 插件（本机 WebSocket 9500）→ 已打开的 Godot 项目
```

服务固定为 `godot-ai==3.2.1`，通过 uvx 启动并使用 `E:\Tools\GodotAI\uv-cache`。Windows 使用 `pythonw.exe` 包装 uvx，保留 MCP 标准输入输出管道并隐藏子进程控制台。配置等待时间为 `startup_timeout_sec = 60`、`tool_timeout_sec = 360`。

核心服务参数如下，仅用于核对；实际执行器绝对路径以本机 Codex 配置为准：

```text
uvx --link-mode copy --from godot-ai==3.2.1 godot-ai attach --port 8000 --ws-port 9500
```

该服务已经预热。维护时保留固定版本与 Windows 无窗口包装，避免误用 PATH 中的另一套 Python 或升级成与项目插件不一致的服务。[官方 Windows 启动配置源码](https://github.com/hi-godot/godot-ai/blob/v3.2.1/plugin/addons/godot_ai/client_configurator.gd)

若需要重建丢失的 `godot-ai` 配置，可用以下无凭据骨架。仅合并该 MCP 段，保留配置中的其他服务器和现有环境选项；迁移后先更新绝对路径。

```toml
[mcp_servers."godot-ai"]
command = 'C:\Python314\pythonw.exe'
args = [
  '-c',
  'import subprocess,sys; raise SystemExit(subprocess.call(sys.argv[1:], stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr, creationflags=0x08000000))',
  'C:\Users\EDY\.local\bin\uvx.exe',
  '--cache-dir', 'E:\Tools\GodotAI\uv-cache',
  '--python', 'C:\Users\EDY\AppData\Roaming\uv\python\cpython-3.12.13-windows-x86_64-none\python.exe',
  '--link-mode', 'copy', '--from', 'godot-ai==3.2.1',
  'godot-ai', 'attach', '--port', '8000', '--ws-port', '9500',
]
enabled = true
startup_timeout_sec = 60
tool_timeout_sec = 360

[mcp_servers."godot-ai".env]
GODOT_AI_DISABLE_TELEMETRY = '1'
```

### 开始使用与连接排查

1. 当前只读会话查询返回空列表。请先保存旧 Godot 编辑器中的工作，再重新打开 `E:\FunBlock Studio\block\project.godot`，使新插件装载，检查 Godot AI dock 中的服务与编辑器连接状态。代理未强制关闭编辑器。
2. 重启 Codex 中对应的 MCP 服务；若当前客户端没有重新加载入口，则重启 Codex，再开新一轮会话加载工具。安装后尚未刷新的当前工具列表不能用于判断配置是否存在。
3. 先做只读确认，例如列出编辑器会话、读取当前项目路径或场景树。确认目标是 Block 项目后，再使用会修改编辑器的工具。
4. 若启动超时，检查 Python/uvx 路径、固定版本缓存和两个端口。端口已占用或被 Windows 保留时，在 Godot AI 的编辑器设置中调整端口，再同步 Codex attach 参数。
5. 只有 MCP 工具目录可见，尚不能证明某个 Godot 编辑器项目在线。应同时核对编辑器会话与项目路径。

Godot AI 默认跳过 headless 启动；源码中的 `GODOT_AI_ALLOW_HEADLESS=true` 是显式开启入口，普通语法/导入检查无需设置。不要为了重复检查而启动 GUI 或执行游戏自动验收。[headless 行为源码](https://github.com/hi-godot/godot-ai/blob/v3.2.1/plugin/addons/godot_ai/plugin.gd#L703)

### 更新与导出

AssetLib 3.2.1 与官方 GitHub 后续大版本的配置可能不同。v4 要求 Godot 4.7+，使用带认证的 stdio attach，不能使用裸 `http://127.0.0.1:8000/mcp` 代替；更新应遵循 [官方迁移说明](https://github.com/hi-godot/godot-ai/blob/main/docs/v4-migration.md)，同时处理插件和客户端配置，不把新目录直接覆盖到已加载的旧插件。

`export_presets.cfg` 已将 `addons/godot_ai/*` 和 `godot-ai-LICENSE.txt` 加入开发工具排除项。该设置尚未通过本轮实际导出包验证；本轮没有重新导出 Windows 游戏。

## Tripo：3D 生成 MCP 与本机登录

本机安装的是 [Tripo 官方文档](https://developers.tripo3d.ai/en/docs/cli) 指定的 npm 包 [`tripo-cli@0.7.0`](https://www.npmjs.com/package/tripo-cli/v/0.7.0)，由 `node.exe` 执行 `dist/cli.js mcp` 提供 stdio MCP。它处理 3D 资产，与 Godot AI 的编辑器连接职责不同。

Codex 全局 MCP 名称为 `tripo`，配置包含：

- 启动参数：`E:\Tools\TripoAI\cli-0.7.0\node_modules\tripo-cli\dist\cli.js mcp`。
- `TRIPO_HOME = E:\Tools\TripoAI\profile`，将配置、账号 profile 和历史留在项目外。
- `TRIPO_ANALYTICS_ENABLED = 0`，关闭 CLI 匿名用量分析。
- `env_vars = ["TRIPO_API_KEY", "TRIPO_REGION"]`，允许从 Codex 启动环境继承 Key 和账号区域。该字段只声明继承变量名，不保存 Key 值；已继承的 `TRIPO_API_KEY` 会优先于本机账号 profile。

用户已明确稍后自行填写 Key。请在本机交互式 PowerShell 运行：

```powershell
powershell -ExecutionPolicy Bypass -File "E:\FunBlock Studio\block\tools\configure_tripo.ps1"
```

脚本调用官方 `login --paste`，以密码输入方式读取 Key，保存到与 Codex MCP 相同的 `E:\Tools\TripoAI\profile`。`--paste` 需要交互终端，不要让无交互的 MCP 调用代替输入。可按账号需要追加 `-Region cn` 或 `-Region ov`；不要把 Key 放进命令参数、聊天、文档或版本库。

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
- 恢复 Godot AI 安装：关闭项目后，按相同 3.2.1 发布包及 SHA256 核对完整目录，再启用。配置或端口变化后同步恢复 attach 参数；不要只替换部分供应商脚本。
- 更换 Tripo 账号：在同一个 `TRIPO_HOME` 下重新登录或使用 CLI 的 profile 管理；需要退出时使用官方 `logout`。若设置了 `TRIPO_API_KEY`，同时核对其优先级，避免仍使用旧账号。
- 迁移电脑：重新准备 uv/Python、Node 和固定版本工具，再更新绝对路径并重新登录。缓存、日志、个人 profile、凭据以及全局配置备份均留在本机，不提交项目仓库；不复制包含 Key 的配置全文到交付记录。

## 核验记录

- 已完成：Godot 4.7.2 无界面编辑器导入退出码 `0`，无 SCRIPT/Parse/Compile 错误；固定版 Godot AI 服务预热；Tripo CLI 安装；Sprite Pipeline 的 Python/Pillow 后处理环境检查；`configure_tripo.ps1` PowerShell 解析通过，未执行登录。
- Godot AI：MCP 初始化、`tools/list` 与 `ping` 通过，列出 46 个工具；HTTP `/godot-ai/status` 返回服务包版本 `3.2.1`。MCP `serverInfo.version` 中的 `3.4.8` 是 FastMCP 版本，不作为 Godot AI 插件/后端包版本。
- Tripo：CLI 0.7.0 的 MCP 初始化、`tools/list` 与 `ping` 通过，列出 5 个工具。检查没有提供 Key，没有发送 `tools/call`，没有创建生成任务。
- Godot 编辑器：额外执行 1 次只读 `session_manage`，参数为 `{"op":"list"}`，返回 `sessions: []`、`count: 0`、`isError: false`。协议与工具调用成功，当前旧 Godot 编辑器尚未装载新插件；本次没有修改编辑器或运行游戏。
- 待用户完成：保存后重新打开 Godot 项目，再重启 Codex MCP 或 Codex 并加载新一轮工具，确认 Block 编辑器会话；Tripo Key 稍后在本机登录。资产生成及游戏界面、操作、声音验收均未执行。
