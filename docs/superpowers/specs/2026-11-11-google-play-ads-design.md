# Google Play 发布与 AdMob 自动复活设计

日期：2026-11-11；状态：用户已确认，开始实现。
依据：`docs/Block-Blast-Godot-Android发布.md`、现有三模式规则、Poing Studios AdMob v5.1.0、Google Play 2026 目标 API 36 与广告/隐私要求。

## 1. 目标

1. 将现有 Godot 4.7.2 Android 项目接入 Google AdMob（Next-Gen SDK）并具备可上传 Google Play 的 AAB 构建链路。
2. 每次新开一局/新进一关的**第一次失败**自动尝试一次插屏广告；广告成功展示并关闭后复活本局，继续游戏。
3. 广告不可用（120 秒冷却中、无填充、加载/展示失败、UMP 同意未完成）时不复活，进入正常失败页。
4. 准备除账号、真实广告 ID、公网托管和 Play 后台操作之外的全部代码、配置、文档与测试。

## 2. 产品与合规决策

- 目标受众：13 岁及以上，不面向儿童，不进入 Google Play Families。
- 广告形态：仅插屏。自动触发的广告不能使用激励视频（激励必须玩家主动选择）；首版不加横幅、开屏广告或额外插屏。
- 广告内容上限 G；`tag_for_child_directed_treatment=false`；不使用个性化广告的儿童配置。
- 频率：每局首次失败尝试一次；两次插屏展示至少间隔 120 秒，跨重启持久化。
- 广告只在失败结算的自然停顿展示，不在启动、退出、游玩中或主动关闭时展示。
- UMP 同意完成后才允许广告；设置提供“广告隐私设置”入口。
- 不承诺 Play 审核通过；真实广告收入与后台审核由用户完成。

## 3. 复活规则

- 仅在 `GameState.status == GAME_OVER` 且本局未使用过复活时可用。
- 清除最多 8 个**非目标标记**的已占格；目标宝石/星星保留，避免破坏收集配额。
- 清除后若托盘为空或没有任何合法落点，重新生成一组带完整可解性认证的托盘；生成失败则放弃复活。
- 保留分数、最高分、目标进度、关卡进度、回合数与失败计数；恢复 `PLAYING`。
- 每局最多一次；第二次失败正常结束，不再触发广告。
- 复活逻辑放在规则层 `GameState.revive_after_failure()`，不依赖广告 SDK，可无头测试。

## 4. 广告架构

- 供应商：Poing Studios `godot-admob` v5.1.0（MIT），Android 使用 GMA Next-Gen `ads-mobile-sdk:1.4.0`，UMP 3.1.0；官方发布含 Godot 4.7.2 Android 原生模板。
- 随项目提交：`addons/admob` 运行时/编辑器代码、`addons/admob/android/bin` 的 4.7.2 AAR 与 package.gd、MIT/第三方 Notice。
- 新增 `scripts/ads/ad_service.gd`（Node）：
  - 仅 Android 且 `ads/enabled=true` 时激活；桌面与无头测试完全空实现。
  - 读取 ProjectSettings 的测试/正式 App ID、插屏 Unit ID、冷却秒数、调试地理、隐私政策 URL。
  - 启动后执行 UMP `ConsentInformation.update` → 需要时 `UserMessagingPlatform.load_consent_form` + `show` → `MobileAds.initialize`。
  - 初始化后预加载插屏；加载失败退避重试；提供 `request_revive_interstitial(callback)`，结果只返回“展示并关闭”或“不可用”。
  - 持久化 `user://ads_state.json` 的 `last_interstitial_unix`；展示成功后写入。
  - 提供 `privacy_options_required()` / `show_privacy_options()`；设置页使用。
  - 不直接操作游戏 UI；通过 signal 通知 `showed`、`dismissed`、`failed`、`privacy_changed`。
- 配置（project.godot）：
  - `[admob] general/android/enabled=true`，`general/android/app_id=<Google 测试 App ID 默认值>`。
  - `[ads] enabled=true`、`use_test_ads=true`、`test_interstitial_id=ca-app-pub-3940256099942544/1033173712`、`real_interstitial_id=""`、`cooldown_seconds=120`、`debug_consent_geography="EEA"`、`privacy_policy_url=""`。
  - 正式发布时用户必须填写真实 App ID/插屏 ID 并把 `use_test_ads` 改为 false。

## 5. 主流程接入

- `main.gd` 新增 `ad_service`，在界面就绪后创建；连接广告信号。
- 每次 `_start_game` 重置本局广告复活尝试标记。
- `_try_show_game_over` 先显示正常失败页，再调用自动复活尝试：
  1. 若本局已尝试、广告不可用或复活条件不满足，保持失败页。
  2. 若插屏未就绪，显示“广告加载中…”模态最多 5 秒；超时/失败/无填充则保持失败页。
  3. 广告展示期间暂停游戏与音乐，关闭后恢复；若成功关闭且 `revive_after_failure()` 成功，切回 `game`，显示“复活成功，继续挑战”；否则保持失败页。
- UMP/广告初始化在菜单阶段进行，失败不影响游戏。
- 设置页新增“广告隐私设置”按钮，仅 UMP 要求时可见/可用；新增“隐私政策”入口仅在配置 URL 后显示。
- 所有新增 UI 文案进入中/英/法词典；广告加载状态不阻塞返回以外的操作。

## 6. 构建与发布

- APK 与 AAB 都使用 Gradle 构建；Android 模板 4.7.2；保持包名 `com.funblockstudio.block`、min 24/target 36、arm64、上传签名和 16KB 对齐。
- `tools/export_android.py`：
  - 为两种格式都安装 Android 源码模板并设置 `gradle_build/use_gradle_build=true`。
  - 暂存项目只启用 `addons/admob/plugin.cfg`，排除 `godot_ai`。
  - 预检插件/原生包/配置；正式 AAB 拒绝测试广告或空正式 ID，测试 APK 需显式 `--allow-test-ads`。
  - 版本升到 `0.9.6`、versionCode 9。
- `export_presets.cfg`：APK 改 Gradle、开 INTERNET、保留 CSV/词典 include、保留签名；AAB 同样。
- 不改现有 `dist` 历史包；新包输出 `Block-0.9.6-android-release.*`。

## 7. 合规与商店准备

- 隐私政策模板：说明设备/广告标识、IP/大致位置、应用交互、诊断信息，Google AdMob 共享、TLS、用户同意与隐私设置、13+ 非儿童向、联系方式。
- `app-ads.txt` 模板：`google.com, pub-<publisher-id>, DIRECT, f08c47fec0942fa0`。
- Data safety 建议：设备或其他 ID（广告 ID、应用集 ID）、大致位置（IP）、应用交互、诊断；用于广告/分析/防欺诈，传输加密，与 Google 共享。
- Play App content：包含广告=是；目标受众 13+；内容分级按问卷；隐私政策 URL；无需登录。
- 用户必须自行完成：Play/AdMob 账号、真实 ID、UMP 消息、网站与文件托管、Play Console 申报、AAB 上传、12 人×14 天封闭测试、正式发布。

## 8. 测试与验收

- 规则测试：复活清格、保留目标、托盘重认证、每局一次、失败后状态。
- 广告服务测试：桌面空实现、冷却持久化、测试/正式 ID 校验、UMP 未完成不放广告、展示失败不复活。
- UI action 测试：首次失败触发自动广告回调、广告成功复活、广告失败保持失败页、每局只一次。
- 全量无头测试、`--check-only`、本地化检查、导出 `--check`；可选构建测试 APK（测试广告）验证 Gradle/AAR。
- 用户验收：真机测试广告、EEA 同意表单、隐私设置、广告关闭后复活、第二次失败不弹广告、Play 审核与收入。

## 9. 非目标

- 激励视频、横幅、开屏广告、广告中介、服务端广告验证、去广告内购、真实服务器排行榜。
- iOS 发布、Play Families、儿童账号、跨设备账号体系。
