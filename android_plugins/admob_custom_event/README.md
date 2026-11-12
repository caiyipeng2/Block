# AdMob 自定义事件测试适配器

按 Google AdMob 自定义事件文档实现的自有测试适配器。它不接第三方广告 SDK，只用于验证 Next-Gen SDK 的 waterfall custom event 链路；真正接入广告网络时替换 `HouseInterstitialAd` 内部的加载/展示实现即可。

- 类名：`com.funblockstudio.block.admob.HouseCustomEventAdapter`
- 参数：`house-test`（AdMob 后台 Parameter 可留空或填任意标签）
- 广告格式：插屏
- 源码：`android_plugins/admob_custom_event/src/main/java/...`
- 构建时由 `tools/export_android.py` 复制到 Android 临时工程的 `src/main/java`，由 Godot Gradle 工程编译；不需要单独 AAR。

## AdMob 后台配置

1. 登录 AdMob，进入 **Mediation → Waterfall sources → Set up ad source → Add custom event**。
2. 添加 mapping：
   - Mapping name：`Block House Test`
   - Class name：`com.funblockstudio.block.admob.HouseCustomEventAdapter`
   - Parameter：`house-test`
3. 在目标 **Mediation group** 中添加自定义事件：
   - Label：`Block House Test`
   - 设置一个测试用 eCPM（例如 `5`）
   - 选择上面的 mapping。
4. 确保应用实际请求的插屏广告单元在该 mediation group 中；直接 AdMob 单元或 Google 测试单元不会走自定义事件。
5. 用测试设备请求该真实广告单元，确认出现“自定义事件测试广告”弹窗；关闭后 AdMob interstitial 应正常回调结束。

## 替换真实广告网络

在 `HouseInterstitialAd.load()` 中初始化第三方 SDK；在 `showAd()` 中调用第三方插屏展示；把第三方的加载成功/失败、展示、点击、关闭回调转发到 `loadCallback` 和 `adCallback`。保留 `initialize()`、`getVersionInfo()`、`getSDKVersionInfo()` 及 `Parameter` 读取逻辑。具体接口参考：

- https://developers.google.com/admob/android/next-gen/custom-events/setup
- https://developers.google.com/admob/android/next-gen/custom-events/interstitial

不要把测试弹窗用于正式广告收入；它只是链路验证器。
