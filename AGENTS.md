# Block 项目开发约定

## 用户确认的验收方式（2026-10-12）

- 默认只做问题定位、代码和逻辑修改，由用户运行 Godot 验收界面、操作和声音。
- 不自动控制桌面，不启动 GUI 进行点击/拖动验收，不运行完整自动验收流程；用户后来明确要求时再执行。
- 可进行必要的语法或编译检查，保持检查轻量；已有测试脚本可以随接口变化维护。
- 交付说明区分“代码已修改”“语法检查通过”和“用户验收通过”，不能混为一谈。
- 使用 `docs/Block-Blast-Godot-需求文档.md` 中已确认的 MVP 规则，交付时更新剩余开发项。

## 远端与提交约定（2026-10-12）

- 用户已授权当前项目及后续开发内容提交并推送到 `https://github.com/caiyipeng2/Block.git`。
- 开发完成并做必要的轻量编译检查后，提交代码、项目资源及文档，推送到 `origin/main`；无需重复询问提交或推送授权。
- Godot/CodeGraph 缓存、临时运行产物、日志、个人存档和凭据留在本地，不提交。
- 禁止强制推送或覆盖已有远端历史；发现新远端提交时先核对并合并。

## Godot AI 与 CodeGraph（2026-10-16）

- CodeGraph 的 Windows 常驻目录监视会阻止 Godot AI 更新器重命名插件目录。MCP 使用 `codegraph serve --mcp --no-watch`，分析前继续手动 `codegraph sync`；不要重新启用该监视器。
- Godot AI 插件与 Python 服务保持同一版本，当前为正式 `4.3.0`，使用带认证的 stdio `attach`；本机端口为 HTTP 8001 / WebSocket 8002。更新和恢复步骤见 `docs/Block-Blast-Godot-MCP配置.md`。
- Tripo CLI 的 LLM 辅助 Key 与 Tripo 3D API Key 分开；本机凭据、传输能力文件、配置备份及失败恢复目录不提交。
