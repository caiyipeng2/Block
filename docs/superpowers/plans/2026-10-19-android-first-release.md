# Android 首次 APK / AAB 交付计划

**Goal:** 构建独立正式签名 APK 与 Google Play AAB，并将 APK 安装到已授权三星手机。

**Architecture:** 现有 0.8.3 代码通过 Android 专属竖屏/渲染特性导出。工具复制私有 staging，移除 Godot AI autoload 和编辑器插件，保留完整资源与 CSV；签名由本机环境变量传入。通过校验后原子发布产物，不上传 Google Play。

**Tech Stack:** Godot 4.7.2、Java 21、Android SDK 36、Build Tools 36.1、NDK 29、Gradle 8.11.1、bundletool 1.18.3、ADB。

- [x] 用户确认首次包名 com.funblockstudio.block 与本机独立上传签名。
- [x] 检测三星 SM-S9280 / Android 16 / arm64，授权连接有效。
- [x] 准备模板、SDK、JDK，签名凭据保存在 Git 忽略且 ACL 受限的 work/android-signing。
- [x] 增加 Android APK / Android AAB 导出预设，versionName 0.8.3、versionCode 1，游戏分类。
- [x] Android 720×1280 竖屏、Compatibility、触摸模拟鼠标；系统返回复用 Esc 暂停/返回逻辑。
- [x] 新增 tools/export_android.py，私有 staging、自包含导出引擎、CSV 保留、脱敏日志、失败半包隔离与原子发布。
- [x] 首轮 APK/AAB 构建通过，APK 已在三星安装，AAB 签名/16KB 页面配置通过；修正游戏分类后重新构建最终包。

最终两种产物验证、三星更新安装、文档与提交推送由本轮可见计划追踪；通过证据记录在 Android 发布说明。APK 安装及静态包检查不等于游戏游玩验收或 Play 后台接收通过。
