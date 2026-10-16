# Block Windows 发布说明

更新：2026-10-16。本页保留第一阶段 `0.1.0` 导出记录；当前源码为 `0.7.1`，按钮改为圆润亮面并修正闯关图标越框，开屏沿用 `0.7.0`，玩法、用户配表、失败辅助和解锁记录保留，尚未重新导出。连胜和地图奖励明确不做；旧包不包含当前玩法与美术。

既有闯关配置从 [`config/adventure_levels.csv`](../config/adventure_levels.csv) 读取 96 关目标数量、难度、模板/镜像、初始特殊格数、种子、前两关分数/填充及失败辅助步长/上限，不按关号公式增长。编辑方法见 [关卡配表说明](Block-Blast-Godot-关卡配表说明.md)。当前 17 列包括 `retry_assist_step` / `retry_assist_max`，默认 20/60，可逐关关闭或调节；旧 15 列表兼容默认值，本轮不修改 CSV。CSV 已设置 Keep 保留原文导入，`export_presets.cfg` 的 include filter 包含该文件，确保将原始 CSV 带入 `.pck`；源表更改后需重新导出，新包不读取包外同名文件，不支持外部热更新。本轮不执行测试、GUI 或完整自动验收，不生成新发布包。

`0.7.1` 将模式按钮改为圆润亮面：移除暗厚底与外部投影，以全周圆弧、同色柔边和渐隐高光表现光泽，按压仅轻沉 1–2px；同时收紧闯关定位点及底弧，包含描边的图形保留在徽章内。MenuModeButton/MainMenu/Main 三份 Godot 4.7.2 `--check-only` 均退出码 0、无脚本错误，独立静态复核无阻断。未运行 GUI、游戏场景、测试用例或导出包，实际材质和尺寸由用户停止旧游戏后按 F5 验收。

历史 `0.7.0` Main、三个菜单脚本及 UI action 测试共 5 份不同脚本 Godot 4.7.2 `--check-only` 均退出码 0，无 SCRIPT/Parse/Compile/Failedload 错误；最后 MainMenu/Main/UI action 三份重检通过，独立静态复核完成。底部重叠/焦点问题已修，五种窗口静态布局公式检查通过；实际字体渲染仍待用户验收。这不表示已导出或运行新 EXE；测试只维护和编译，本轮未运行游戏场景、测试用例、GUI 或打包。`0.6.9` 失败辅助、`0.6.8` 读表修复及更早证据保留在验收记录，不能代替本版运行验收。

开屏与菜单均由 Godot 原生矢量绘制，未引入外部图片、字体或视频依赖；源代码验收须覆盖首次开屏/跳过、返回不重播、三个模式/设置/退出、键盘焦点和窄窗口，再进行发布包验收。

目标为 Windows x86_64、鼠标操作，沿用 Forward Plus / D3D12。本机 `0.1.0` release/debug 已实际导出并打包，包完整性检查通过；独立 EXE、声音、存档与跨机运行仍待用户验收。真实检查结果见 [验收记录](Block-Blast-Godot-验收记录.md)。本轮未启动导出游戏或控制桌面验收。

## 发布前准备

1. 使用项目当前开发版本 **Godot 4.7.2 stable**，并安装同版本导出模板。不要使用其他 Godot 版本的模板代替。
2. 在 Godot 中打开项目，使用“编辑器 → 管理导出模板”安装对应模板；也可从已下载的匹配 `.tpz` 文件安装。
3. 使用 **Python 3.10 或更新版本**运行 `tools/export_windows.py`。脚本仅依赖 Python 标准库，不需要安装第三方包。
4. 核对 `project.godot` 的 `application/config/version` 和 `export_presets.cfg` 的 `Windows Desktop` 预设。发布配置为 `release`，调试配置为 `debug`，架构均为 `x86_64`。
5. 用 Excel/WPS 另存“CSV UTF-8（逗号分隔）”，可带 BOM；普通 CSV 若保存为 GBK/GB18030 会被拒绝。确认连续 1–96 关且无重复/缺失，保持 Keep 导入设置和 `config/adventure_levels.csv` 导出包含规则。先按 F5 验证点击闯关、开局/重开、读表报错与玩法，再导出；现版不能仅追加第 97 行扩关。

Godot 默认 Windows 模板根目录为 `%APPDATA%\Godot\export_templates`，模板按引擎版本存放。本机默认目录未安装匹配模板；历史 `0.1.0` 发布阶段已下载官方 4.7.2 模板包并核对 SHA512，Windows 模板提取到本地 `work/release-templates/4.7.2.stable`，当时已通过预检并用于导出，未安装到全局模板目录；后续使用时追加下文 `--templates-dir` 参数。

## 推荐：一条命令导出并打包

在项目根目录执行，将示例引擎路径替换为本机实际路径：

```powershell
python tools/export_windows.py --godot "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --configuration release
```

只检查引擎、项目、预设和模板，不执行导出：

```powershell
python tools/export_windows.py --godot "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --configuration release --check
```

生成调试包：

```powershell
python tools/export_windows.py --godot "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --configuration debug
```

模板安装在自定义目录时，追加 `--templates-dir "<匹配版本的模板目录>"`。这里必须指定版本目录本身，不能指定它的父目录，例如：

```powershell
python tools/export_windows.py --godot "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --configuration release --templates-dir "work/release-templates/4.7.2.stable"
```

该目录应含 `version.txt`、`windows_debug_x86_64.exe`、`windows_release_x86_64.exe`，以及官方模板随附的其他文件。预检要求版本与当前配置的模板可用；若存在可选 DLL，也会逐个核对。不要自行重命名模板或依赖文件，也不要仅提供一个 `.exe`。

本轮官方 4.7.2 模板包不含独立 DLL，当前使用 Windows 系统 D3D12 运行库。这不表示所有 Godot 版本或自定义模板均无需 DLL；若导出生成 DLL 或 `x86_64` 子目录，交付时仍须完整带上。渲染配置保持 Forward Plus / D3D12。

`--templates-dir` 只改变本次导出的模板来源。脚本在临时项目副本中覆盖 `custom_template`，不改全局模板安装，也不把本机绝对路径写入原工程；不会下载或安装模板。此参数不改变渲染器或玩法配置。

脚本从项目读取版本号，先做预检，再调用 Godot 对应的 `--export-release` 或 `--export-debug`，最后打包导出目录。检查失败时根据报错补齐条件后重试，不应把残留旧文件当作新版本成功产物。

## 输出与交付

当前 `0.1.0` 的 release 输出为：

```text
build/windows/0.1.0/release/                  导出与打包输入目录
dist/Block-0.1.0-windows-x86_64-release.zip   交付压缩包
```

历史 `0.1.0` release ZIP 为 **42,205,896 字节**，debug ZIP 为 **38,531,861 字节**。当时两包 ZIP CRC、`build-info.json` 中的文件 SHA256 及 ZIP 旁 `.sha256` 校验均匹配。此结果只证明历史版本导出与打包完成，不替代用户启动验收，也不表示存在 `0.7.1` 发布包。

当前 release 包实际成员为 `Block.exe`、`Block.pck`、`build-info.json`、`START-HERE.txt`、`licenses/GODOT-LICENSE.txt`、`licenses/GODOT-COPYRIGHT.txt`；debug 包另外包含 `Block.console.exe`。本轮两包没有独立 DLL 或 `x86_64` 目录，使用 Windows 系统 D3D12。

debug 对应路径中的配置名为 `debug`，不会与 release 混用。包内包含游戏可执行文件、独立 `.pck` 和其他导出文件；如果 Godot 生成依赖 DLL 或 `x86_64` 子目录，也随包保留。另有：

- `START-HERE.txt`：运行方法、操作与存档说明。
- `build-info.json`：构建信息和运行文件的 SHA256 清单。
- ZIP 旁同名 `.sha256` 文件：用于核对整个压缩包内容。

将压缩包完整解压到一个可读目录，再按 `START-HERE.txt` 启动游戏可执行文件。不要在压缩包中直接运行，也不要只复制 `.exe`；`.pck` 和其他随附文件须完整保留并保持相对位置；若包内含 DLL 或 `x86_64` 子目录，也同样保留。接收方无需安装 Godot 编辑器。

包中的 SHA256 清单用于核对文件内容，不是代码签名。本轮没有配置 Windows 代码签名；导出包也不能作为其他 Windows 版本、显卡或驱动均已兼容的证明。

`build/`、`dist/`、导出日志和缓存只留在本地，不纳入代码仓库。脚本、项目资源、导出预设和本文档提交到项目远端；发布二进制不自动上传为 GitHub Release。

## 在 Godot 中手动导出

打开“项目 → 导出”，选择已提交的 `Windows Desktop` 预设，确认模板已安装、架构为 `x86_64`，选择“导出项目”。面向玩家时关闭“带调试导出”，调试包则启用该选项。保留导出目录全部文件。

也可以直接使用 Godot 命令行。先创建目标目录，再执行；以下方式只导出，不会生成本项目的说明、清单与 ZIP：

```powershell
New-Item -ItemType Directory -Force -Path "build/windows/manual-release"
& "E:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path . --export-release "Windows Desktop" "build/windows/manual-release/Block.exe"
```

调试导出使用 `--export-debug`，并选择单独的输出目录。需要完整交付包时优先使用项目 Python 打包入口。

## 存档与设置

最高分、设置、闯关进度和逐关失败次数由游戏写入 `user://savegame.json`；Windows 上通常位于 `%APPDATA%\Godot\app_userdata\Block\`。格式仍为 version 1，旧档缺少失败计数时默认 0；失败立即尝试保存，通关只清该关计数，保存失败沿用仅本次运行提示。游戏包不包含开发者的个人存档，解压目录中也无需附带 `savegame.json`。当前版本不保存进行中的棋局。

更新版本时保留同一应用名及存档路径，已有最高分和设置可继续读取；若修改应用名或启用自定义用户目录，应另行确认存档迁移需求。

## 由用户完成的发布验收

在没有安装 Godot 编辑器的 Windows x86_64 机器上完整解压 release 包，依次确认：

1. 游戏能够启动至主菜单，文字、棋盘与托盘显示完整；新包核对首次开屏、跳过不误开模式、返回不重播，三个模式/设置/退出与键盘焦点在窄窗口均可用。
2. 合法放置立即加分，清除再加分；非法放置不加分；新三块、暂停/继续和 Game Over 操作正常。
3. 音效、音乐、减少动画开关可用，窗口缩放后鼠标落点正确。
4. 创造最高分或修改设置，正常退出再启动，记录能够读取。
5. Game Over 标题、计分明细、“重新开始”和“返回菜单”可见可用。
6. 若验收后续 `0.7.1` 包，先确认打包时的 CSV 目标、开局模板与参数被正确读取，不依赖编辑器导入缓存；目标、难度和辅助以打包时实际表为准，不套用历史初始基线。错误表在源码中应明确定位并拒绝闯关、不清旧局，自由/经典仍可进入；不要用包外同名 CSV 期待覆盖 `.pck` 内配置。
7. 回归 Next Level 返回地图、完成横带/青块归位/新关点亮与手动开始、只播一次及各种取消清理；小方格塔、窄窗与进度保存；托盘同尺、表扬和 50%/90% 丝带、旧块稳定、最后落子/胜利及收集飞行。自动目标→HUD→棋盘入场可跳过且不穿透；收集 HUD 按表展示 1–4 类、不显示加分浮字，真实明细在暂停查看。前两关局部救援、自由/经典原池和失败规则保留；不出现连胜或地图奖励。
8. 第 3 关起真实 Game Over 后下局辅助增加并封顶，跨运行保留；进行中主动重开/退出/暂停不计，通关后只重置本关，旧档兼容。辅助参数下局才生效，不减少目标、不更改计分、不替换当前剩余托盘或引入一格救援，仍可失败且不显示降难度提示。前两关、其他关和自由/经典隔离。

反馈时附上包版本、debug/release、Windows 版本、显卡/驱动，以及错误内容或截图。当前渲染基线为 Forward Plus / D3D12；触控、Compatibility 兼容方案和 P1 玩法扩展继续保留在后续范围。
