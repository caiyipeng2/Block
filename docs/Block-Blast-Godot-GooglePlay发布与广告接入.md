# Block Google Play 发布与 AdMob 接入

更新：2026-11-11  
包名：`com.funblockstudio.block`  
源码版本：`0.9.6` / Android `versionCode 9`  
目标：Android 16 / API 36，最低 API 24，仅 `arm64-v8a`

## 1. 当前已经接入的内容

- Poing Studios Godot AdMob v5.1.0（MIT）及 Godot 4.7.2 原生模板，固定随项目保存。
- GMA Next-Gen SDK 1.4.0、Google UMP 3.1.0。
- 插屏广告：每局首次失败自动尝试一次；两次展示至少间隔 120 秒；广告成功展示并关闭后才复活。
- 冷却中、无填充、加载失败、UMP 未完成时正常进入失败页；第二次失败不再弹广告。
- 自动触发使用插屏而不是激励视频；广告只在失败结算的自然停顿出现，并设 120 秒冷却。若 Play 审核认为强制插屏过于打扰，最小改动是改为玩家点击后观看激励视频再复活（需要同意流程和同样的冷却）。
- 复活规则：最多清 8 个非目标格；保留目标标记、分数和进度；必要时重新生成可解托盘。
- 设置中的“广告隐私设置”（UMP）和“隐私政策”（配置 URL 后显示）。
- Gradle APK/AAB 导出、测试广告防误发预检、Data safety/隐私政策/app-ads.txt/商店文案模板。

## 2. 文件与配置

| 内容 | 位置 |
|---|---|
| 广告服务 | `scripts/ads/ad_service.gd` |
| AdMob/UMP 原生包装 | `scripts/ads/admob_backend.gd` |
| 复活规则 | `scripts/rules/game_state.gd` |
| 广告插件 | `addons/admob/` |
| 插件 Notice | `packaging/notices/POING-ADMOB-NOTICE.txt` |
| 测试 | `tests/run_ad_service_tests.gd`、`tests/run_ad_revive_tests.gd` |
| 隐私政策模板 | `docs/privacy-policy-template.md` |
| app-ads.txt 模板 | `docs/app-ads.txt` |
| 商店文案 | `docs/store-listing.md` |

### 2.1 测试广告（默认）

项目默认使用 Google 官方测试 App ID 与测试插屏单元：

- App ID：`ca-app-pub-3940256099942544~3347511713`
- 插屏：`ca-app-pub-3940256099942544/1033173712`

`project.godot`：

```ini
[ads]
enabled=true
use_test_ads=true
test_interstitial_id="ca-app-pub-3940256099942544/1033173712"
real_interstitial_id=""
cooldown_seconds=120
debug_consent_geography="EEA"
privacy_policy_url=""
```

测试 APK 必须显式加 `--allow-test-ads`；正式 AAB 不带该参数，脚本会拒绝测试广告或空正式 ID。

### 2.2 替换正式广告 ID（必须由你完成）

1. 在 AdMob 后台创建应用，包名填 `com.funblockstudio.block`。
2. 创建 **插屏广告单元**，记下 App ID（带 `~`）和插屏 Unit ID（带 `/`）。
3. 修改 `project.godot`：

```ini
[admob]
general/android/enabled=true
general/android/app_id="ca-app-pub-你的16位~你的10位"

[ads]
enabled=true
use_test_ads=false
real_interstitial_id="ca-app-pub-你的16位/你的10位"
```

`admob` 设置是 Android Manifest 的 App ID；`real_interstitial_id` 是运行时广告位。不要把测试 ID 和正式 App ID 混用。

## 3. AdMob 后台

1. 注册/登录 AdMob，添加应用。
2. Privacy & messaging → 创建并发布适用于 EEA/英国/瑞士的 UMP 消息；确认消息状态为已发布。
3. 将测试设备加入 AdMob 测试设备，或仅使用 Google 测试广告；不要点击自己的真实广告。
4. 记录 App ID 的发布商 ID（`ca-app-pub-` 后 16 位），用于 app-ads.txt。
5. 上线后观察 AdMob 的广告请求、填充、eCPM 和政策中心；不要频繁手动刷新或自点。

## 4. 隐私政策、app-ads.txt 与商店网站

1. 复制 `docs/privacy-policy-template.md`，替换开发者名称、邮箱、网站和生效日期。
2. 由你或法律顾问确认后托管到公开 HTTPS 页面。
3. 将 `docs/app-ads.txt` 中的 `pub-` 数字替换为 AdMob 发布商 ID，并放到开发者网站根目录：
   `https://你的域名/app-ads.txt`
4. 在 Google Play 商店资料的“开发者网站”填写同一域名；AdMob 通常最多 24 小时完成爬取。
5. 把隐私政策 URL 填入 Play Console，并写入 `project.godot` 的 `ads/privacy_policy_url`，游戏设置才会显示入口。

## 5. 构建

### 5.1 测试 APK（测试广告）

```powershell
python tools/export_android.py --godot "<Godot 4.7.2 路径>" --sdk "<Android SDK>" --java "<JDK17+>" --keystore "work/android-signing/block-upload.jks" --credentials-file "work/android-signing/credentials.json" --format apk --allow-test-ads
```

输出：`dist/Block-0.9.6-android-release-test.apk`。仅用于内部测试，文件名带 `test`，不要上传 Play。本轮已验证 APK 86MB/SHA256 `e6357e8598b48f8a3436a3f7cad4102f1427ed5ed1936989a5b1b15495176cb7` 和测试 AAB 40MB/SHA256 `e7d90dde05163661a4cfcf37830bb595e07da9fb5104ba212dccdb200629e746`；两者均只含测试广告，实际文件在 `work/verification/ads-test/`。

### 5.2 正式 AAB

先完成第 2.2 节；然后**不要**加 `--allow-test-ads`：

```powershell
python tools/export_android.py --godot "<Godot 4.7.2 路径>" --sdk "<Android SDK>" --java "<JDK17+>" --keystore "work/android-signing/block-upload.jks" --credentials-file "work/android-signing/credentials.json" --format aab
```

输出：`dist/Block-0.9.6-android-release.aab`。先运行 `--check` 可以在不导出时检查配置。

构建脚本会：
- 安装 Godot 4.7.2 Android 源码模板；
- 只启用 AdMob 编辑器插件，排除 Godot AI；
- 使用 Gradle 构建 APK/AAB；
- 校验测试广告/正式 ID、插件 AAR、CSV/词典、ZIP CRC；
- 生成 `work/android-export/<format>/build-info.json`。

AdMob AAR 会合并以下权限（无用户可见的运行时授权弹窗）：

- `android.permission.INTERNET`
- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.AD_ID`
- `com.google.android.gms.permission.AD_ID`
- `android.permission.READ_BASIC_PHONE_STATE`（普通权限）
- `android.permission.WAKE_LOCK`
- `android.permission.FOREGROUND_SERVICE`

Data safety 和广告 ID 申报必须按 AdMob 官方数据披露与 Play Console 最新表单填写，不能因为应用本身不读取这些数据就忽略 SDK 的自动收集。

签名密钥、`credentials.json`、玩家存档和构建缓存不要提交 Git。

## 6. Google Play Console 操作顺序

1. 注册 Google Play 开发者账号并完成身份验证；订阅/付款资料按后台要求完成。
2. 创建应用，包名 `com.funblockstudio.block`，默认语言与游戏一致。
3. 上传 AAB 到内部测试轨道；接受 Play App Signing，妥善备份本地 upload keystore。
4. 完成 **App content**：
   - 隐私政策：填公开 URL。
   - 应用访问：无需登录，全部内容可用。
   - 广告：选择“包含广告”。
   - 内容分级：按问卷如实填写；本游戏为益智、无暴力/社交/赌博。
   - 目标受众：13 岁及以上，不面向儿童。
   - 数据安全：见第 7 节。
   - 新闻/COVID/政府等声明：不适用。
5. 填写商店资料：标题、短/长描述、截图、功能图、图标、类别、联系方式、开发者网站。
6. 先内部测试：安装测试 APK 或内部测试 AAB，验证真实设备。
7. 新个人开发者账号按 Play 要求进行 **12 名测试者连续 14 天**封闭测试，然后申请生产访问。
8. 提交生产审核；审核通过后分阶段发布并观察崩溃/ANR/广告政策。

## 7. Data safety 建议

以 AdMob 官方数据披露和 Play Console 最新表单为准；本游戏 13+、非儿童向、无账号、无自有服务器：

- 设备或其他 ID：收集并共享（广告 ID、应用集 ID；用于广告、分析、防欺诈）。
- 大致位置：收集并共享（由 IP 推断；不采集精确位置）。
- 应用交互：收集并共享（启动、点击、视频观看等）。
- 诊断：收集并共享（性能/崩溃相关）。
- 传输加密：是（TLS）。
- 账号/删除请求：本游戏无账号；本地数据可通过系统清除应用数据删除。广告 ID 可由用户在 Android 设置中重置/删除；如表单要求删除请求 URL，按你的实际情况填写并咨询合规人员。

不要为了“看起来简单”而勾选“不收集数据”；AdMob SDK 会自动收集上述信息。

## 8. 设备验收清单

- [ ] 安装测试 APK，确认启动不崩溃，菜单/设置/三模式正常。
- [ ] 首次失败：出现插屏；关闭后自动复活，棋盘清出空间，当前托盘可放。
- [ ] 复活后分数/目标/关卡进度保留；第二次失败不再弹广告。
- [ ] 120 秒内再次首次失败：不弹广告、不复活，进入正常失败页。
- [ ] 无网络、无填充、广告加载失败：不复活，正常失败。
- [ ] EEA 测试地理：UMP 表单出现；同意/拒绝后广告行为符合预期；设置→广告隐私设置可重新打开。
- [ ] 广告期间游戏和音乐暂停，关闭后恢复；返回/暂停/系统返回不误触。
- [ ] 桌面版无广告请求、无 AdMob 错误；无头测试全通过。
- [ ] 真机检查 Android 返回、后台切换、竖屏安全区、声音和存档。

## 9. 你无法交给代码完成的事项

- 注册 Play/AdMob 账号、身份验证、付款资料。
- 创建真实广告单元、UMP 消息、测试设备。
- 公网托管隐私政策与 app-ads.txt，填写开发者网站。
- Play Console 所有声明、截图/功能图、AAB 上传、测试轨道、12×14 天封闭测试、生产审核。
- 真实广告收入、政策审核结果和商店排名。
