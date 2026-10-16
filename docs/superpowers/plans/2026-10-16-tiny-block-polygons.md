# 极小方块多边形修复

**Goal:** 修复消除碎片触发 `block_art.gd draw_block: Invalid polygon data, triangulation failed` 的重复报错。

**Architecture:** 在共享 BlockArt 入口修复小尺寸几何，不删报错、不停粒子、不改变游戏逻辑。极小格用简单矩形；斜面厚度按扣除边框后的可用面限制，确保中心面有正面积。

**Tech Stack:** Godot 4.7.2 / GDScript CanvasItem。

- [x] 定位截图第 42–45 行四个斜面 polygon；消除碎片的半径缩小会反复进入约 2px 尺寸。旧 side=2.1 时 rim=.55、face≈1、bevel=.525，center=-.05；side=2.2 时中心宽为0，导致交叉或重合顶点。
- [x] 共享 `draw_block()` 的简单矩形阈值改为 4px，斜面上限额外按 face 最短边的 .25 限制，使中心宽高至少为 face 的一半。
- [x] 只读核对同文件特殊格/标记的小尺寸分支，排除同根当前调用风险。
- [x] 必要脚本 Godot `--check-only` 和独立静态复核，不运行游戏、用例或 GUI。
- [x] 更新原因、验收与剩余清单；提交推送由可见计划和最终记录确认。

正常棋盘、托盘和拖动方块尺寸的既有材质保持，规则、供块、反馈时长和粒子数量不改。运行时错误清零由用户停止旧游戏、清空旧调试记录后 F5 验收，不能用语法检查代替渲染验收。
