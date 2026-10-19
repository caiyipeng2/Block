# 特殊图案清晰度修复实施计划

**Goal:** 修复特殊图案在实际棋盘、托盘和目标栏尺寸下的阶梯边与碎裂切面，向已批准的右列预览靠拢。

**Architecture:** 保留 BlockArt 的绘制接口及 embedded 分流；将现场绘制的小三角面替换为透明 SVG 图集。资源级 CanvasTexture 固定线性 mipmap 采样，避免依赖宿主节点或改全局渲染。底托、布局、规则与反馈时序保持现有实现。

**Tech Stack:** Godot 4.7.2、SVG、CanvasTexture、GDScript。

## 1. 根因与边界

- [x] 核对用户实机截图、批准图右列及当前源码：旧图案是未抗锯齿的现场三角面，非 PNG 压缩问题。
- [x] 确认 canvas_items 拉伸没有低分辨率 Viewport 放大；薄槽壁和密集高反差小切面是主要问题。
- [x] 独立审计确认共享入口可覆盖各场景，CanvasTexture 可单独固定过滤。

## 2. 生产资源与接入

- [x] 新建 `assets/ui/targets/target_symbols.svg`：四列红六角星/黄五角星/金橙五边形/蓝钻，两行分别为嵌槽和独立符号；使用宽亮暗面，透明留白隔开每格。
- [x] 新建 `target_symbols.tres`，使用无损纹理、线性 mipmap、禁重复，不依赖每帧生成或节点过滤属性。SVG 以 2× 导入，实际 512px/格。
- [x] 在 `scripts/ui/block_art.gd` 以图集区域绘制替换旧槽环/星冠三角绘制，保持透明度、受光脉冲、四像素保护和居中短边等比适配。
- [x] 保留五处 embedded 和七处独立调用、非法重叠保护、底托后绘图案顺序。

## 3. 验证

- [x] 无界面资源导入后检查 SVG 及 import 设置；只导入资源，不运行游戏。实际 12 级 mipmap，已查看引擎原生 64/32px 单元，核对渐变和透明边。
- [x] `--headless --script res://scripts/ui/block_art.gd --check-only` 以及 Main、MoveFeedback、GameplayControls、CollectionFlights、已有 UI action 的相同轻量语法检查均退出 0。
- [x] 独立静态复核图集坐标、透明边、过滤、全调用链及导出资源可达性，无 P1/P2。
- [x] 已记录用户实机验收仍待进行：停止旧游戏后 F5 对照棋盘/托盘/HUD/飞行；不自动控制 GUI 或执行用例。

## 4. 交付

- [x] 更新 0.8.3 版本、README、需求、验收记录、剩余逻辑开发和美术说明，明确批准图与实机验收的差别。

提交及正常推送 `origin/main` 由本轮 Codex 可见计划分别追踪，完成证据以 Git 历史和远端引用为准。生产 SVG/import/tres 随代码交付，缓存、日志和个人存档排除。
