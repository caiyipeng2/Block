# Windows 0.1.0 发布准备 Implementation Plan

**Goal:** 为已验收的鼠标版 MVP 提供可重复的 Windows x86_64 导出与 ZIP 打包入口。

**Architecture:** `project.godot` 是版本号唯一来源；`export_presets.cfg` 维护 Windows Desktop 参数。Python 标准库脚本先核对引擎/模板与配置，再执行无界面导出，递归打包整个输出目录并生成文件散列清单。运行验收由用户完成。

**Tech Stack:** Godot 4.7.2、Windows Desktop export、Python 3 标准库、Git。

1. 核对 `project.godot`、引擎 `--version`、模板目录及 Godot 官方 Windows 导出参数。保留 Forward Plus/D3D12。
2. 在 `project.godot` 设置 `config/version="0.1.0"`；新增 Windows Desktop x86_64 导出预设，使用独立 PCK，不将测试、文档、构建输出或开发工具放进游戏包。
3. 新增 `tools/export_windows.py`：支持 `--godot`、`--configuration debug|release`、`--check`、`--templates-dir`；检查模板完整性和版本，输出到版本/配置专用目录，拒绝复用非空目录以免混入旧产物；生成 ZIP、游玩说明、构建信息及 SHA256。
4. 执行 Python 语法检查与真实工具链预检。模板存在时执行 headless 导出；模板缺失时记录准确阻塞条件，不运行游戏或自动验收。
5. 更新 README、Windows 发布说明、剩余开发与验收记录；记录用户已通过 Game Over 修复。实际 EXE 启动、声音、存档和显示由用户验收。
6. 审查 diff，按已授权约定提交和推送 `origin/main`，核对本地与远端提交。

用户已授权直接继续开发。本计划不要求额外确认、不运行完整自动验收、不实现 P1 扩展。
