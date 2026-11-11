# Google Play 与 AdMob 自动复活 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline execution chosen; subagents unavailable in this session). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Godot 4.7.2 游戏接入 Poing AdMob v5.1.0（Next-Gen）+ UMP，并实现每局首次失败自动插屏复活、可上传 Google Play 的 AAB 构建链路。

**Architecture:** 第三方 AdMob 插件与 4.7.2 原生库固定随项目提交；`AdService` 封装 UMP/初始化/插屏/冷却；`GameState.revive_after_failure()` 独立负责规则层复活；`main.gd` 只在首次失败时串起“失败页 → 自动广告 → 复活/保持失败”。构建脚本负责 Gradle 模板、插件启用、测试广告防误发和 AAB 校验。

**Tech Stack:** Godot 4.7.2 / GDScript、Poing Studios godot-admob v5.1.0、GMA Next-Gen SDK 1.4.0、UMP 3.1.0、Gradle/Android API 36、Python export tooling。

**Spec:** `docs/superpowers/specs/2026-11-11-google-play-ads-design.md`

## Global Constraints

- 目标受众 13+、不面向儿童；广告内容上限 G；不进入 Families。
- 只使用插屏；不使用激励视频自动播放、横幅或开屏广告。
- 每局首次失败最多尝试一次；两次展示至少间隔 120 秒，跨重启持久化。
- 冷却中、无填充、加载/展示失败、UMP 未完成时不复活。
- 复活清最多 8 个非目标标记格；保留目标标记、分数与进度；每局一次。
- 桌面/无头测试绝不请求广告；真实 Play AAB 不得使用测试广告 ID。
- 包名 `com.funblockstudio.block`；minSdk 24、targetSdk 36、arm64、版本 0.9.6 / versionCode 9。

---

### Task 1: 固定第三方 AdMob 插件与原生库

**Files:**
- Create: `addons/admob/**`（v5.1.0）
- Create: `addons/admob/android/bin/**`（android-template-v4.7.2）
- Create: `packaging/notices/POING-ADMOB-NOTICE.txt`
- Modify: `project.godot`（editor_plugins / admob / ads 配置）
- Modify: `addons/admob/android/.gitignore`（允许提交 bin）

**Interfaces:**
- Produces: `res://addons/admob/gdscript/src/api/MobileAds.gd`（class_name MobileAds）等运行时类；`admob/general/android/app_id` 项目设置。

- [ ] 从固定 SHA256 的 `poing-godot-admob-v5.1.0.zip` 解压 `addons/admob`，从 `android-template-v4.7.2.zip` 解压内容到 `addons/admob/android/bin`。
- [ ] 保留 MIT LICENSE；写 notice，记录版本、来源 URL、zip SHA256、GMA Next-Gen 1.4.0。
- [ ] `project.godot` 启用 `res://addons/admob/plugin.cfg`，加入 `[admob] general/android/enabled=true`、测试 App ID；加入 `[ads]` 测试插屏 ID、`use_test_ads=true`、`cooldown_seconds=120`、`debug_consent_geography="EEA"`、空 `real_interstitial_id`/`privacy_policy_url`。
- [ ] 运行 `godot --headless --path . --check-only --script res://scripts/main.gd`，确认插件不破坏解析。
- [ ] Commit。

### Task 2: AdService（UMP + 插屏 + 冷却）

**Files:**
- Create: `scripts/ads/ad_service.gd`
- Create: `tests/run_ad_service_tests.gd`
- Modify: `tests/run_checks.py`

**Interfaces:**
- Produces:
  - `configure(host: Node, now_unix: int = -1) -> void`
  - `bool is_available()`
  - `bool can_attempt_revive()`
  - `void request_revive_interstitial(callback: Callable) -> void`（callback(bool shown_and_dismissed)）
  - `bool privacy_options_required()`
  - `void show_privacy_options()`
  - signals `ad_started`, `ad_ended`, `state_changed`
  - 测试注入 `set_backend_for_test(backend)`、`set_clock_for_test(callable)`。

- [ ] 测试：桌面 `OS.has_feature("android")==false` 时 `is_available()==false` 且不创建插件；冷却 120 秒；`use_test_ads` 选择测试 Unit ID；缺正式 ID 时不可用；UMP 未完成不请求；展示失败回调 false。
- [ ] 运行测试确认失败。
- [ ] 实现 AdService：仅 Android；UMP `ConsentInformation.update`；`UserMessagingPlatform.load_consent_form`/`show`；`MobileAds.initialize`；`InterstitialAdLoader` 预加载；`FullScreenContentCallback` 驱动 started/ended；`user://ads_state.json` 持久化 `last_interstitial_unix`；`--allow-test` 逻辑不放在运行时，运行时只读设置。
- [ ] 运行测试通过；加入 `run_checks.py` suite `ad-service`。
- [ ] Commit。

### Task 3: GameState 复活规则

**Files:**
- Modify: `scripts/rules/game_state.gd`
- Modify: `tests/run_mode_state_tests.gd`

**Interfaces:**
- Produces:
  - `func can_revive() -> bool`
  - `func revive_after_failure(max_clear: int = 8) -> bool`
  - `var revive_used := false`
- 行为：只允许 `status==GAME_OVER` 且未用过；清除最多 8 个非 `target_cells` 的已占格；托盘为空/无合法落点时重新生成认证托盘；失败返回 false 且保持 GAME_OVER；成功恢复 PLAYING。

- [ ] 在 mode-state 测试加：首次复活清格且保留目标标记、分数/进度不变、托盘有完整解、第二次返回 false；无空间可救时 false。
- [ ] 运行 `python tests/run_checks.py --suite mode-state` 确认失败。
- [ ] 实现复活；复用 `_fill_regular_tray`/`_fill_collection_tray`，失败时尝试更多清格但不超过非目标已占格；全部失败保持 GAME_OVER。
- [ ] 运行 mode-state 通过；Commit。

### Task 4: 主流程首次失败自动广告

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/gameplay_controls.gd`（广告加载态/失败页恢复）
- Modify: `scripts/audio/feedback_audio.gd`（广告期间暂停/恢复）
- Modify: `assets/localization/messages.json`
- Modify: `tests/run_ui_action_tests.gd`

**Interfaces:**
- Consumes: `AdService.request_revive_interstitial`、`GameState.can_revive/revive_after_failure`。
- Produces: `main.ad_service`、`_auto_revive_attempted`、`_try_auto_revive_after_failure()`。

- [ ] 在 `_start_game` 重置 `_auto_revive_attempted=false`；`game.revive_used` 由 GameState 保证每局一次。
- [ ] `_try_show_game_over` 显示失败页后调用一次自动尝试；广告展示时 `paused=true`、`feedback_audio.set_ad_pause(true)`；结束后恢复；成功复活切回 `screen="game"`、清空失败覆盖层、刷新 HUD、显示“复活成功，继续挑战”。
- [ ] 若 `can_attempt_revive()` false / 广告失败，保持失败页，不显示复活按钮或免费复活。
- [ ] UI action 测试：用 fake AdService 注入，首次 game over 调用一次广告；成功回调后 `game.status==PLAYING`、screen game；失败回调保持 game_over；同局第二次 game over 不调用。
- [ ] 运行 ui suite；Commit。

### Task 5: 设置页广告隐私入口

**Files:**
- Modify: `scripts/ui/settings_panel.gd`
- Modify: `scripts/main.gd`
- Modify: `assets/localization/messages.json`
- Modify: `tests/run_ui_action_tests.gd` / localization tests

**Interfaces:**
- SettingsPanel signal `ad_privacy_requested`、`privacy_policy_requested`；AdService `privacy_options_required()`/`show_privacy_options()`。

- [ ] 增加“广告隐私设置”按钮（仅 UMP 要求时可见/可用）和“隐私政策”按钮（仅配置 URL 时可见）；主场景连接。
- [ ] 中/英/法文案；本地化测试覆盖。
- [ ] 运行 ui/localization；Commit。

### Task 6: Gradle 导出、测试广告防误发与版本

**Files:**
- Modify: `export_presets.cfg`
- Modify: `tools/export_android.py`
- Modify: `project.godot`（version 0.9.6）
- Modify: `tests/run_checks.py`（如需）
- Docs later.

**Interfaces:**
- CLI: `python tools/export_android.py ... --format apk|aab [--allow-test-ads]`.
- Preflight errors: missing addon/bin; test ads with AAB; empty real IDs; invalid app/unit ID; APK/AAB not Gradle.
- Staging: copy addons/admob, exclude godot_ai; install Android source template for both formats; enable only `res://addons/admob/plugin.cfg`.

- [ ] 改两个 preset：APK `use_gradle_build=true`/format 0，AAB format 1；min/target 24/36；internet true；exclude filter 保留 admob、排除 godot_ai；version 0.9.6/code 9。
- [ ] 改 export script：`--allow-test-ads`；AAB 无该 flag 时要求 `ads/use_test_ads=false` 且真实 ID 有效；APK 允许测试但必须显式 flag；两种格式都安装模板、设置 gradle。
- [ ] 运行 `python tools/export_android.py ... --check`（无测试标志）应报告测试广告阻止正式 AAB；带 `--allow-test-ads --format apk --check` 通过。
- [ ] Commit。

### Task 7: 隐私/商店/操作文档

**Files:**
- Create: `docs/privacy-policy-template.md`
- Create: `docs/app-ads.txt`
- Create: `docs/Block-Blast-Godot-GooglePlay发布与广告接入.md`
- Create: `docs/store-listing.md`
- Modify: `docs/Block-Blast-Godot-Android发布.md`
- Modify: `docs/Block-Blast-Godot-验收记录.md`
- Modify: `docs/Block-Blast-Godot-剩余逻辑开发.md`

- [ ] 写隐私政策模板（AdMob 数据、UMP、13+、联系方式占位）；app-ads.txt 模板；Play Console 分步清单；Data safety/内容分级建议；商店文案/素材清单；真实/测试 ID 替换说明；12×14 天测试说明。
- [ ] 更新验收/剩余项，明确用户验收和 Play 后台操作。
- [ ] Commit。

### Task 8: 全量验证与可选测试 APK

- [ ] `python tests/run_checks.py --suite all`。
- [ ] `python tools/check_localization.py`；所有改动 GDScript `--check-only`。
- [ ] `python tools/export_android.py ... --check --allow-test-ads --format apk`；条件允许时实际构建测试 APK（测试广告），检查 AAR/manifest/INTERNET/AD_ID、AAB 结构、签名；不启动 GUI。
- [ ] 记录未验证项：真实广告、UMP 表单、真机、Play 审核、收入。
- [ ] Commit + push。
