# Block Windows 发布说明

更新：2026-10-15。本页保留第一阶段 `0.1.0` 导出记录；当前源码为 `0.6.4` 模式间托盘统一、清除表扬和进度丝带，玩法沿用 `0.6.0`，尚未重新导出。连胜和地图奖励明确不做；旧包不包含当前玩法与美术。

本轮只调整托盘与显示反馈，不执行测试、GUI 或完整自动验收，不生成新发布包。先由用户停止旧游戏后按 **F5** 验收模式间托盘同尺、清除表扬分级和 50%/90% 一次丝带，通过后再按本页流程导出。

`0.6.4` clear_praise/Feedback/progress_banner/HUD/Main/UI action 测试 6 份不同脚本 `--check-only` 均退出码 0，无脚本/解析/编译/加载失败错误，最后 4 项重检通过；最终独立静态审查完成、无阻断问题。未执行测试用例、GUI 或导出包，不代表实机通过，也不表示已导出或运行 `0.6.4` EXE。

目标为 Windows x86_64、鼠标操作，沿用 Forward Plus / D3D12。本机 `0.1.0` release/debug 已实际导出并打包，包完整性检查通过；独立 EXE、声音、存档与跨机运行仍待用户验收。真实检查结果见 [验收记录](Block-Blast-Godot-验收记录.md)。本轮未启动导出游戏或控制桌面验收。

## 发布前准备

1. 使用项目当前开发版本 **Godot 4.7.2 stable**，并安装同版本导出模板。不要使用其他 Godot 版本的模板代替。
2. 在 Godot 中打开项目，使用“编辑器 → 管理导出模板”安装对应模板；也可从已下载的匹配 `.tpz` 文件安装。
3. 使用 **Python 3.10 或更新版本**运行 `tools/export_windows.py`。脚本仅依赖 Python 标准库，不需要安装第三方包。
4. 核对 `project.godot` 的 `application/config/version` 和 `export_presets.cfg` 的 `Windows Desktop` 预设。发布配置为 `release`，调试配置为 `debug`，架构均为 `x86_64`。

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

历史 `0.1.0` release ZIP 为 **42,205,896 字节**，debug ZIP 为 **38,531,861 字节**。当时两包 ZIP CRC、`build-info.json` 中的文件 SHA256 及 ZIP 旁 `.sha256` 校验均匹配。此结果只证明历史版本导出与打包完成，不替代用户启动验收，也不表示存在 `0.6.4` 发布包。

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

最高分和设置仍由游戏写入 `user://savegame.json`；Windows 上通常位于 `%APPDATA%\Godot\app_userdata\Block\`。游戏包不包含开发者的个人存档，解压目录中也无需附带 `savegame.json`。当前版本不保存进行中的棋局。

更新版本时保留同一应用名及存档路径，已有最高分和设置可继续读取；若修改应用名或启用自定义用户目录，应另行确认存档迁移需求。

## 由用户完成的发布验收

在没有安装 Godot 编辑器的 Windows x86_64 机器上完整解压 release 包，依次确认：

1. 游戏能够启动至主菜单，文字、棋盘与托盘显示完整。
2. 合法放置立即加分，清除再加分；非法放置不加分；新三块、暂停/继续和 Game Over 操作正常。
3. 音效、音乐、减少动画开关可用，窗口缩放后鼠标落点正确。
4. 创造最高分或修改设置，正常退出再启动，记录能够读取。
5. Game Over 标题、计分明细、“重新开始”和“返回菜单”可见可用。
6. 若验收后续 `0.6.4` 包，先确认模式间托盘同尺、消费/命中/回弹与窄窗正确、清除表扬和 50%/90% 丝带一次触发，再回归旧块稳定、最终落子/胜利及独立收集飞行。
7. 核对第 3/4/5 关配额 24/30/36，后续阶梯增至 120；自动目标→HUD→棋盘入场可跳过且不穿透，收集界面返回/gear、暂停真实设置及胜利布局完整。收集关不显示加分浮字，真实积分与明细仍在暂停查看。前两关仍为 368/392 分与局部救援，自由/经典保持原池和失败规则；不出现连胜或地图奖励。

反馈时附上包版本、debug/release、Windows 版本、显卡/驱动，以及错误内容或截图。当前渲染基线为 Forward Plus / D3D12；触控、Compatibility 兼容方案和 P1 玩法扩展继续保留在后续范围。
