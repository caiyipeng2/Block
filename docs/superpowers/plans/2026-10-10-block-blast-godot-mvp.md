# Block Blast 风格 Godot MVP Implementation Plan

> 2026-10-12 状态说明：下文保留最初计划与历史检查步骤。当前代码实现与剩余事项以 `docs/Block-Blast-Godot-剩余逻辑开发.md` 为准；用户已改为自行运行验收，后续只做代码修改和必要编译检查，不再自动执行本文中的 GUI/测试流程。动画由 `scripts/ui/move_feedback.gd` 实现，HUD 与状态面板由 `scripts/ui/gameplay_controls.gd` 实现，拖放协调留在 `main.gd`；不再按最初拆分创建 DragController/HUD/Modal 空壳。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在当前 Godot 4.7 工程中实现一个 Windows 鼠标优先的 8×8 方块消除 MVP，并保证每轮三块至少存在一种可自由选择顺序、最终放完三块的方案。

**Architecture:** 将规则层保持为无场景依赖的 GDScript 类：棋盘占用、落子校验、行列清除、计分、游戏结束和本轮可解性搜索都通过明确的数据结构和纯方法完成。Godot `Control` 视图层只负责显示、鼠标拖放和事件反馈；规则层发出结果后，视图层播放动画并锁定输入，避免动画直接改写逻辑状态。第一版不实现触控、旋转、特殊方块和断点续局。

**Tech Stack:** Godot 4.7、GDScript、Control/CanvasItem 2D UI、`user://savegame.json`、Godot headless script assertions。

---

## 文件结构

### 规则层

- Create: `scripts/rules/piece_data.gd` — 3–5 格方块的不可变数据与局部坐标。
- Create: `scripts/rules/board_rules.gd` — 8×8 棋盘、边界/重叠检查、落子副本、行列扫描和清除。
- Create: `scripts/rules/scoring.gd` — 基础分、同时清除倍率和连击状态。
- Create: `scripts/rules/round_generator.gd` — 三块候选生成、任意顺序可解性搜索、重试和保底组。
- Create: `scripts/rules/game_state.gd` — 当前棋盘、三块托盘、分数、回合状态和结束判定。

### Godot 视图层

- Create: `scenes/main.tscn` — 唯一启动场景。
- Create: `scripts/main.gd` — 主菜单、游戏视图、暂停和 Game Over 的路由。
- Create: `scripts/ui/game_screen.gd` — HUD、棋盘、托盘和拖放协调。
- Create: `scripts/ui/board_view.gd` — 8×8 绘制、占用格、预览和清除动画。
- Create: `scripts/ui/piece_tray.gd` — 三块待放方块绘制与鼠标命中区域。
- Create: `scripts/ui/drag_controller.gd` — 鼠标拖动状态机、吸附、非法回弹和输入锁。
- Create: `scripts/ui/hud.gd` — 分数、最高分、连击、暂停/重开按钮。
- Create: `scripts/ui/modal.gd` — 暂停与 Game Over 弹窗。

### 持久化与测试

- Create: `scripts/persistence/save_repository.gd` — 最高分和设置版本化读写。
- Create: `tests/run_rules_tests.gd` — 可由 Godot headless 执行的规则断言入口。
- Modify: `project.godot` — main scene、窗口基准尺寸、输入动作和版本信息。

## Task 1: 建立 Godot 启动配置和规则测试入口

**Files:**
- Modify: `project.godot`
- Create: `tests/run_rules_tests.gd`

- [ ] **Step 1: 写出会失败的最小测试入口**

创建测试脚本，要求缺少规则类时以明确错误退出，并预留以下断言辅助函数：

```gdscript
extends SceneTree

func _initialize() -> void:
    _assert_true(false, "规则层尚未实现")
    quit(1)

func _assert_true(value: bool, message: String) -> void:
    if not value:
        push_error("FAIL: " + message)
        quit(1)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
    if actual != expected:
        push_error("FAIL: %s; actual=%s expected=%s" % [message, actual, expected])
        quit(1)
```

- [ ] **Step 2: 运行测试确认它因功能缺失失败**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd`  
Expected: 非零退出，并输出 `规则层尚未实现`。如果 `godot` 不在 PATH，先使用本机 Godot 4.7.2 可执行文件的绝对路径重跑，不把“命令未找到”当作测试通过。

- [ ] **Step 3: 更新项目启动配置**

在 `project.godot` 设置：

```ini
[application]
run/main_scene="res://scenes/main.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input]
pause={"deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":4194307)]}
restart={"deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":82)]}
back_to_menu={"deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":4194305)]}
```

保留现有 Godot 4.7 / Forward Plus / Windows D3D12 配置；不要为第一版加入触控映射。

## Task 2: 实现棋盘、方块和行列清除规则

**Files:**
- Create: `scripts/rules/piece_data.gd`
- Create: `scripts/rules/board_rules.gd`
- Modify: `tests/run_rules_tests.gd`

- [ ] **Step 1: 写失败测试覆盖核心规则**

测试必须覆盖：8×8 棋盘、3–5 格方块、越界/重叠拒绝、合法落子、完整行、完整列、行列交叉格去重、清除后剩余方块不下落。

```gdscript
var board := BoardRules.new(8)
var line_piece := PieceData.new(Vector2i(0, 0), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])

_assert_true(board.can_place(line_piece, Vector2i(0, 0)), "空棋盘可放置")
_assert_true(not board.can_place(line_piece, Vector2i(7, 0)), "越界形状不可放置")
board.place(line_piece, Vector2i(0, 0), 2)
_assert_true(not board.can_place(line_piece, Vector2i(0, 0)), "重叠形状不可放置")
```

使用测试辅助方法构造一条满行和一组同时满行/满列的棋盘，断言 `clear_full_lines()` 返回去重后的坐标集合及行列数量。

- [ ] **Step 2: 运行测试确认失败原因来自缺少类/方法**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd`  
Expected: 非零退出，错误应指向 `BoardRules` 或 `PieceData` 尚未定义，而不是测试脚本语法错误。

- [ ] **Step 3: 实现最小规则接口**

`PieceData` 暴露 `cells: Array[Vector2i]` 和 `cell_count()`；`BoardRules` 暴露：

```gdscript
func can_place(piece: PieceData, origin: Vector2i) -> bool
func place(piece: PieceData, origin: Vector2i, color_id: int) -> void
func get_legal_origins(piece: PieceData) -> Array[Vector2i]
func clear_full_lines() -> Dictionary
func duplicate_board() -> BoardRules
```

棋盘使用 `Array[Array[int]]` 保存 `-1` 为空，非负整数为颜色索引；`place()` 只接受已经通过 `can_place()` 的完整形状。`clear_full_lines()` 同时收集满行与满列，交叉格只清一次，并返回 `{cells, rows, columns}`。

- [ ] **Step 4: 运行测试确认通过**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd`  
Expected: 输出规则测试通过，退出码为 0。

## Task 3: 实现计分、任意顺序可解性搜索和 GameState

**Files:**
- Create: `scripts/rules/scoring.gd`
- Create: `scripts/rules/round_generator.gd`
- Create: `scripts/rules/game_state.gd`
- Modify: `tests/run_rules_tests.gd`

- [ ] **Step 1: 写失败测试固定用户确认的生成约束**

测试至少包含：

```gdscript
var generator := RoundGenerator.new(1234)
var round := generator.generate_solvable_round(BoardRules.new(8))
_assert_equal(round.size(), 3, "每轮恰好三块")
_assert_true(generator.has_any_solution(BoardRules.new(8), round), "新一轮至少存在一种可解排列")

var state := GameState.new()
_assert_true(state.has_legal_move_for_any_remaining_piece(), "只要任意剩余方块可放就不能结束")
```

构造一个必须先放第二块、再放第一块、最后放第三块的测试局面，证明求解器不能只检查托盘原顺序。再构造所有剩余方块都无合法落点的局面，断言 Game Over。

- [ ] **Step 2: 运行测试确认失败**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd`  
Expected: 非零退出，错误指向 `RoundGenerator` 或 `GameState` 尚未实现。

- [ ] **Step 3: 实现计分和求解器**

`Scoring` 固定以下可配置默认值：基础分 `cleared_cell_count * 10`，同次清除 `line_count` 的倍率 `1.0 + 0.5 * (line_count - 1)`，有效落子未清线时连击重置。`RoundGenerator.has_any_solution()` 深度优先枚举三块的所有排列、所有合法起点，并在每一步复制棋盘、放置、清线；只有能放完三个索引不同的方块才算本轮可解。

```gdscript
func has_any_solution(board: BoardRules, pieces: Array[PieceData]) -> bool
func generate_solvable_round(board: BoardRules) -> Array[PieceData]
```

`GameState` 只在三块全部消耗后生成下一组；每次落子结算后，若剩余方块的合法落点集合全部为空才进入 `GAME_OVER`。玩家可从托盘任意位置选择方块。

- [ ] **Step 4: 运行测试确认通过**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd`  
Expected: 规则、计分、任意顺序可解性和结束判定全部通过，退出码为 0。

## Task 4: 创建 Godot 主场景、棋盘视图和鼠标拖放

**Files:**
- Create: `scenes/main.tscn`
- Create: `scripts/main.gd`
- Create: `scripts/ui/game_screen.gd`
- Create: `scripts/ui/board_view.gd`
- Create: `scripts/ui/piece_tray.gd`
- Create: `scripts/ui/drag_controller.gd`

- [ ] **Step 1: 写视图冒烟测试场景**

创建最小 `Main.tscn`，启动后显示一个 8×8 空棋盘、三块托盘方块和分数标签；暂时不加入装饰动画。测试入口通过 `get_tree().current_scene` 检查 `BoardView`、`PieceTray` 和 `HUD` 节点存在。

- [ ] **Step 2: 运行 headless 场景确认缺少节点/脚本**

Run: `godot --headless --path . --editor --quit`  
Expected: 在场景和脚本未建立前失败；记录具体解析错误，避免把导入警告误判为通过。

- [ ] **Step 3: 实现最小可玩视图**

`BoardView` 使用 `Control._draw()` 绘制棋盘与格子，棋盘矩形根据可用区域较小边计算，保持正方形；`PieceTray` 为每块方块维护命中矩形。`DragController` 只接受鼠标：按下进入拖动、移动计算棋盘局部坐标并显示预览、合法释放调用 `GameState.place_piece()`、非法释放在 150–250 ms 内回托盘。动画期间锁定落子输入。

- [ ] **Step 4: 运行 Godot 场景冒烟**

Run: `godot --path . --editor --path .` 后手动验证开始、拖动合法方块、非法回弹和一次消除；若没有可用 Godot GUI，使用 `godot --headless --path . --editor --quit` 先验证场景可加载，并记录 GUI 验证未执行。

## Task 5: 完成菜单、暂停、Game Over、最高分和设置存档

**Files:**
- Implemented: `scripts/main.gd` — 现有场景中的 HUD/结束面板，原生菜单 Button 和设置 CheckButton。
- Implemented: `scripts/persistence/save_repository.gd` — 版本化存档、字段校验、临时文件替换、可选隔离路径。
- Implemented: `scripts/audio/feedback_audio.gd` — 音效与基础循环音乐实际播放控制。
- Test: `tests/run_ui_action_tests.gd`、`tests/run_save_tests.gd`、`tests/run_audio_tests.gd`、`tests/run_exit_tests.gd`。
- Run: `tests/run_checks.py` — 可靠核验 Godot 退出码、完成标记、脚本错误与资源泄漏，30 秒超时。

- [x] **Step 1: 写失败的存档和状态测试**

覆盖无存档启动、最高分写入/读取、设置写入/读取、损坏 JSON 回退默认值；覆盖暂停不改变棋盘、重开清空本局、Game Over 显示分数和最高分。

- [x] **Step 2: 运行测试确认失败**

实际记录：存档路径契约失败退出码 1；字段/临时替换用例失败退出码 1；菜单设置用例缺隔离路径时退出码 1。日志在 `work/verification/`。

- [x] **Step 3: 实现版本化存档和 UI 状态**

存档写入 `user://savegame.json`，字段为 `{version, high_score, sound_enabled, music_enabled, reduced_motion}`；读取失败时安全回退。设置切换控制实际 AudioStreamPlayer 和界面淡入；保存失败时界面明确提示。设置支持鼠标、Tab、空格，Esc 关闭设置；主菜单支持开始、设置和退出。

- [x] **Step 4: 运行测试确认通过**

Run: `python tests/run_checks.py --suite all`  
Expected: 规则、UI、存档、音频和退出五套全部通过，无脚本错误或资源泄漏；真实 GUI 验证设置退出重启后保留，最高分不丢失。

2026-10-12 实际结果：五套退出码均为 0；UI 33 项检查、存档 20 用例、音频 10 用例通过。真实 GUI 完成鼠标、Tab/空格、Esc、退出和重启验证，测试前设置已恢复。详见 `docs/Block-Blast-Godot-验收记录.md`。

本项不等同于完成整个 MVP：清除/回弹动画、重开确认和 Windows release 导出仍按需求后续实现/验收。

## Task 6: Windows 运行与发布验证

**Files:**
- Modify: `project.godot` — 版本号、窗口与导出相关设置。
- Create: `export_presets.cfg` — Windows x86_64 debug/release 预设（若 Godot 编辑器生成则保留其格式）。
- Create: `docs/Block-Blast-Godot-验收记录.md` — 记录真实运行结果和未执行项目。

- [ ] **Step 1: 运行全规则测试和场景加载检查**

Run: `godot --headless --path . --script res://tests/run_rules_tests.gd` 以及 `godot --headless --path . --editor --quit`。  
Expected: 两条命令退出码均为 0，无脚本解析错误。

- [ ] **Step 2: 手动执行 Windows MVP 冒烟**

按顺序验证：主菜单 → 开始 → 鼠标拖放 → 行/列清除 → 得分/连击 → 三块耗尽补充可解新组 → 无剩余合法落点 Game Over → 重开 → 最高分保留。记录 1280×720、1920×1080 和窄窗口结果；触控不作为第一版通过条件。

- [ ] **Step 3: 导出 Windows x86_64 release**

使用 Godot 4.7.2 匹配的 export templates 导出到 `build/windows/`，在无编辑器机器运行，确认图标、版本号、`user://` 存档和 D3D12 启动结论。

- [ ] **Step 4: 更新验收记录并完成交付检查**

验收记录必须区分“已通过”“未执行”“已知限制”，不能把未运行的触控、Compatibility 或 release 测试写成通过。

## Plan self-review

- 需求覆盖：8×8、空棋盘、三块、3–5 格、不旋转、评分/连击、任意顺序可解性、无合法落点结束、Windows 鼠标、菜单/暂停/重开/最高分、最高分与设置存档、触控和扩展保留均有对应任务。
- 可解性定义：求解器枚举三块的任意排列，而不是强制托盘顺序；每一步使用正式放置和清线规则。
- 规则与视图边界：规则层不依赖场景；视图不直接修改棋盘数组；动画阶段锁定输入。
- TDD：每个规则/存档实现任务先写失败测试、确认失败，再写最小实现并重新运行。
- 发布边界：第一版保留 Forward Plus / Windows D3D12；触控与 Compatibility 只记录为后续扩展或验证项。
