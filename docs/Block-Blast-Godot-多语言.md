# Block Blast 多语言配置

当前版本 `0.9.0` 支持 `zh_CN`、`en`、`fr`。设置中的语言下拉框立即切换，偏好写入现有存档的 `language` 字段；缺失或非法值会回退到中文，不改变旧版成绩、闯关记录或设置。

翻译源文件是 `assets/localization/messages.json`，JSON 的键是游戏原始显示文本，值包含 `en` 和 `fr`。中文使用键本身作为默认文本。新增可见文字时必须保持同一源文本，并在 JSON 中补齐两个语言；带 `%d`、`%s` 的占位符要保持顺序和类型，换行也要保持一致。CSV 的难度名称同样需要词典条目。

菜单按钮中文继续使用已确认的图片字形；英语和法语使用同一按钮材质的清除区域绘制文字。长法语内容由运行时按宽度缩放或换行，目标介绍、暂停和失败汇总允许两行。没有随包加入外部字体，使用 Godot SystemFont 回退以避免字体授权和设备缺字问题。

可重复检查：

```powershell
python tools/check_localization.py
& "C:/Users/EDY/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --check-only --script tests/run_localization_tests.gd --log-file work/localization-20261020/localization-tests.log
```

测试使用 `work/localization-20261020/test-save.json`，不会写入玩家的 `user://savegame.json`。当前隔离检查覆盖三种语言、菜单/设置/选关、三模式HUD、最终落子提示（Final Block）、目标介绍、暂停/失败/胜利、确认框、长法语排版、状态保持、存档往返和缺失键。
