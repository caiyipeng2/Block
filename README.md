# Block

Godot 4.7 的桌面方块消除游戏：拖动方块、填满行或列并消除，无时间限制。

项目仓库：[caiyipeng2/Block](https://github.com/caiyipeng2/Block)。本地交付、提交和推送状态以本次交付记录为准。

## 在 Godot 中运行

1. 使用 Godot 4.7 打开项目管理器，点击“导入”，选择项目根目录的 `project.godot`。当前开发使用 Godot 4.7.2 stable。
2. 打开项目后按 **F5**，进入主菜单；点击“开始游戏”。
3. 从下方托盘按住一块方块，拖到棋盘合法位置后释放。

默认面向 Windows 桌面鼠标输入，渲染配置为 Forward Plus / D3D12。

## 玩法与操作

- 默认 8×8 空棋盘，每轮提供三块 3–5 格方块；可自由选择放置顺序，三块全部用完后补充下一轮。
- 方块不能旋转。只有整个形状在棋盘内且不与已有方块重叠时才能放置；非法释放会回弹到托盘，棋盘与分数不变。
- 完整行和完整列同时清除，交叉格只计一次；其他方块保持原位，不下落。
- 合法放置按本次放置格数 × 10 立即加基础分，清除格数 × 10 作为额外分；同时清除多条线时倍率只作用于清除分。3 格落子不清除得 30 分，补满一条 8 格行得 30 + 80 = 110 分；非法释放不加分。连续有效落子都清线时连击增加，不清线的有效落子重置连击。
- 玩家可自由选择托盘中的方块；新的一组三块至少有一种放置顺序与落点组合，逐步落子、清线后能全部放完。玩家操作后，所有剩余方块均无合法落点时结束本局。
- **Esc** 暂停/继续；**R** 请求重新开始。进行中的重开和返回菜单需要确认，Game Over 后可直接选择下一步。
- HUD、暂停和 Game Over 使用原生按钮，支持 **Tab** 切换焦点、**Enter/Space** 激活。动画期间阻止重复落子，暂停和继续仍可用。
- 设置提供音效、音乐、减少动画和试听音效；最高分与设置保存到 `user://savegame.json`，本版不保存进行中的棋局。

## 配置入口

默认规则资源为 [`config/default_rules.tres`](config/default_rules.tres)，类型定义在 [`scripts/rules/game_rules_config.gd`](scripts/rules/game_rules_config.gd)。可在 Godot Inspector 中编辑棋盘尺寸、托盘数量、形状池及方向、计分、生成重试次数、色板/主题和动画时长；默认落子 0.12 秒、清除 0.22 秒、非法回弹 0.20 秒。

默认配置对应已确认的 MVP。调整参数后需按目标玩法重新验收，不能沿用默认配置的结论。

规则层位于 `scripts/rules/`。生成器最近一轮的 `last_solution` 记录完整放置顺序，每步包含原始 `piece_index` 与棋盘 `origin`；`last_diagnostics` 记录 `seed`、`round`、`attempts`、`fallback_used`、`reason`、`nodes_elapsed`、`duplicate_candidates` 与 `elapsed_ms`，用于复现生成问题和调参。

## Windows 导出与打包

安装 **Python 3.10 或更新版本**及与当前 Godot **4.7.2 stable** 匹配的导出模板后，在项目根目录运行（将引擎路径换为本机实际路径）：

```powershell
python tools/export_windows.py --godot "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --configuration release
```

加 `--check` 仅预检、不导出；`--configuration debug` 生成调试包。版本号来自 `project.godot`，当前为 `0.1.0`。发布包输出到 `dist/Block-0.1.0-windows-x86_64-release.zip`，须完整解压后按 `START-HERE.txt` 运行，保留 `.pck` 和所有随附文件；若导出生成 DLL 或 `x86_64` 子目录，也须完整保留。包内 `build-info.json` 含文件 SHA256，ZIP 旁 `.sha256` 用于核对压缩包。

本轮 release/debug 均已实际导出并打包完成，文件 SHA256、ZIP CRC 与压缩包校验值均匹配；尚未启动导出的游戏。当前本机使用已校验的 `work/release-templates/4.7.2.stable` 模板，重新打包时追加 `--templates-dir "work/release-templates/4.7.2.stable"`。模板安装、包结构和用户验收步骤见 [Windows 发布说明](docs/Block-Blast-Godot-Windows发布.md)，检查证据见 [验收记录](docs/Block-Blast-Godot-验收记录.md)。

## 当前开发状态（2026-10-14）

MVP 逻辑、放置与清除分别计分、HUD 明细及 Game Over 布局修复已实现。用户最新确认 Game Over 面板修复验收通过；Windows 发布配置、预检和打包工具已交付，本机 `0.1.0` release/debug 包已生成，待用户运行独立 EXE 与跨机验收。

按用户约定，只进行必要的轻量编译与静态检查；实际界面、输入、声音和导出包启动由用户验收，不自动控制桌面或运行完整自动验收。

## 文档入口

- [需求文档](docs/Block-Blast-Godot-需求文档.md)：已确认的 MVP 规则、验收标准与保留扩展。
- [验收记录](docs/Block-Blast-Godot-验收记录.md)：历史真实检查、用户反馈和本轮证据边界。
- [剩余逻辑开发与用户验收清单](docs/Block-Blast-Godot-剩余逻辑开发.md)：当前待验收项、Windows 发布工作与 P1 范围。
- [Windows 发布说明](docs/Block-Blast-Godot-Windows发布.md)：模板、release/debug 导出、打包及无编辑器运行验收。

后续工作为 Windows 导出包与目标机器验收、按反馈修复；触控、旋转/翻转、断点续局、特殊方块和线上功能保留到 P1 及以后。
