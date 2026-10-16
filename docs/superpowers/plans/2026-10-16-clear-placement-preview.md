# 三模式消除放置预览实施计划

**Goal:** 按参考视频补强所有模式拖放前的变色与发光清除边框。

**Architecture:** 规则与 `ClearColorResolver` 保持不变，Main 将同一合法模拟结果交给纯表现 `ClearPreview`。边缘缓存使用格坐标，绘制时按实时棋盘矩形换算；暂停/取消沿现有生命周期清理。

**Tech Stack:** Godot 4.7.2 / GDScript，原生 CanvasItem 程序化绘制，无新增美术资源、字体或插件。

使用 subagent-driven-development 分工：视频只读分析、光框 helper、已有检查维护分别归独立代理，Main 集成与交付由根代理负责。用户已指定参考效果并授权实施，按项目要求仅做轻量编译与静态复核。

- [x] 视频粗时间线及关键帧分析，记录同色单线/多线彩虹、切入移出时机及原有选色规则。
- [x] 新建 `scripts/ui/clear_preview.gd`：`configure(cell_colors, row_colors, column_colors, board_size, palette)`、`advance(delta)`、`reset()`、`is_active()`、`highlight(reduced_motion)` 和 `draw(canvas, board_rect, reduced_motion)`；缓存暴露边及去重行列分隔，静态减少动画分支。
- [x] 集成 `scripts/main.gd`：合法模拟后 configure，非法/取消 reset，活动非暂停时 advance，预览与拖动块共用 highlight，棋盘绘完后绘制光边。
- [x] 维护 `tests/run_ui_action_tests.gd` 中实际拖动预览断言，覆盖三模式行/列/交叉、只读状态、非法与取消/暂停清理；只维护不执行。
- [x] 对 helper、Main 和维护后的检查脚本执行 Godot `--headless --check-only`，独立静态复核无规则变化与生命周期残留。
- [x] 更新 README、需求、模式、验收和剩余清单；提交及推送状态由可见计划与最终交付记录确认。

验证命令形态：`Godot_v4.7.2-stable_win64.exe --headless --path "E:/FunBlock Studio/block" --log-file "E:/FunBlock Studio/block/work/verification/<script>-placement-preview-syntax.log" --script res://<script>.gd --check-only`。必须等待实际进程退出，核对退出码 0 与无 SCRIPT/Parse/Compile/Failedload 错误。不启动 GUI、不调用 `tests/run_checks.py`。
