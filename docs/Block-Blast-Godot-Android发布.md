# Android APK / AAB 发布

首次交付：2026-10-19；当前交付版本 `0.8.8`，Android `versionCode=6`。APK/AAB均从干净提交 `99a851b513782c1bd639ba465849cde849608a53` 导出，沿用首次确认的包名和独立上传签名；三星SM-S9280已更新并核对开屏录屏及紧凑菜单。

## 文件与用途

- `dist/Block-0.8.8-android-release.apk`：手机更新安装。
- `dist/Block-0.8.8-android-release.aab`：Google Play 后台上传。
- 两包旁有 `.sha256`；最终字节数、SHA256和实际校验摘要见 `dist/Block-0.8.8-android-build-info.json`。两包正式签名、API/16KB、CRC及资源检查均通过；三星安装版本已核对为0.8.8(6)，安装的base.apk哈希与交付文件一致。

包名 `com.funblockstudio.block`，版本 `0.8.8 (6)`；Android7/API24起，目标Android16/API36，仅 `arm64-v8a`，游戏分类。Android采用720×1280竖屏基准、Compatibility/OpenGL ES3、触摸模拟鼠标，系统返回复用Escape暂停/返回逻辑。不申请网络或存储权限。

0.8.8首次开屏放慢为3.60秒，旋转拼块放大30%；手机三模式按钮目标宽66%（此前80%），空间足够时在下方预留未来More行，选中白色外框移除。候选启动日志暴露的Logo极小星芒三角化错误经数值诊断后修复，最终8秒前台开屏录屏及进程日志未再出现。未代点击模式或操作关卡进度。

0.8.7将设置及重开/返回/退出确认改成蓝色圆角弹窗：顶部三图标开关、绿色纵向按钮、真实设置保存及短屏滚动。手机触摸隐藏焦点边框，键盘/手柄导航保留可见焦点。候选真机截图暴露的原生滑块残留、滚动溢出和首次提示换行高度已修，最终设置卡截图无残留和多余留白。未代玩、清除存档或完成关卡；完整游玩、声音与其他设备仍待用户验收。

0.8.6使用AI生成并经审阅选定的原创九格阶梯图案：青色立体方块、中央暖金底托镶青钻、底部珊瑚色整行消除，突出实际玩法。传统图标 `assets/ui/launcher/block-puzzle-original.png` 为1254×1254，SHA256为 `c165e4e73a52d30d064eefdd23b2f299ddffcddbf4a1603cb919f82534c0abe1`；Android自适应前景使用提取出的透明主体 `block-puzzle-foreground.png`，等比放入432×432画布的(64,64)起304×304区域（终点368,368），与独立蓝底分层，避免不透明方形背景产生接缝。来源和导入设置见 [图标说明](../assets/ui/launcher/README.md)。

0.8.5采用竞品官方图标的方向已被用户撤回；旧官方PNG及旧自适应资源从运行资源中移除，不进入新包。此轮为视觉差异化调整，不保证Google Play审核通过。音乐修复、手机适配、玩法和存档保持。

三星 **SM-S9280 / Android16** 当前1080×2340、450dpi。0.8.3首包出现约13秒闪退，已从两次tombstone精确定位到背景音乐PCM循环尾后帧读取；0.8.4将终点改为最后可读帧。用户明确授权后，候选版在真机前台运行超过7分钟，音频活动记录约437秒，无新崩溃；已核对菜单/结束面板截图。有限观察不代表全部玩法验收，具体包源码快照以构建记录为准。

手机适配采用DisplayServer安全区和物理窗口交集，再逆变换到逻辑坐标；摄像头和导航栏保底留白，48dp操作按钮、可读字号、较宽弹窗、统一托盘单格与整槽触控。模拟触摸拖动上提64dp，绘制/预览/释放共用anchor，系统取消触摸只撤销、不落子。桌面尺寸分支与三模式玩法保持。

AAB **尚未上传或经Play Console接收**。本轮完成本地校验后，在Google Play对应应用的测试轨道/版本页上传上述 `.aab`，再按后台完成Play App Signing、商店资料与内容声明。本轮不包含后台账号操作。

## 构建与校验

0.8.8已重新完成以下包校验，证据见 `dist/Block-0.8.8-android-build-info.json` 和本地日志，不沿用候选包或更早包的校验结果。原创图标沿用0.8.6资源；本轮图标未修改。

- Godot4.7.2正式匹配模板，Java21、SDK Platform36、Build Tools36.1.0、NDK29.0.14206865；模板Gradle8.11.1 / AGP8.6.1。
- APK：ZIP CRC、apksigner v2/v3正式签名、`zipalign -c -P 16 -v 4`。
- AAB：bundletool1.18.3 validate、JAR签名与证书一致，`PAGE_ALIGNMENT_16K`。
- 两包的arm64原生库全部PT_LOAD对齐16384；CSV与源码一致，没有Godot AI autoload、编辑器插件、私钥或凭据文件。
- 公共上传证书SHA256：`7773132a390543e7873217549578b53ed9f61391770fa4301c7a6de8854c1d51`。
- 详细日志和快照在 `work/android-export/`，不提交Git。

依据：[Google Play目标API要求](https://developer.android.com/google/play/requirements/target-sdk)、[16KB页面要求](https://developer.android.com/guide/practices/page-sizes)。本地包校验不代表Play后台所有商店条件已通过。

## 本机上传签名

`work/android-signing/` 受本机账户ACL限制并被Git忽略：

- `block-upload.jks`：RSA3072上传私钥库，PKCS12格式。
- `credentials.json`：本机alias/password；不要提交或粘贴到聊天。
- `block-upload-certificate.pem`：公开证书。

请安全备份以上三项。后续上传使用同一上传密钥，并将两个预设的 `version/code` 同时递增，下一次至少为 `7`。启用Play App Signing后，后台应用签名与本地上传密钥可能不同；本地APK使用上传密钥签名。

## 重新打包

```powershell
python tools/export_android.py --godot "C:/Users/EDY/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --sdk "D:/Unity/Editor/Data/PlaybackEngines/AndroidPlayer/SDK" --java "D:/java" --keystore "work/android-signing/block-upload.jks" --credentials-file "work/android-signing/credentials.json" --format apk
```

末尾改为 `--format aab` 构建Bundle；加 `--check` 仅预检。已有同名文件拒绝覆盖，先备份或递增版本。原生APK的Gradle SDK字段留空以使用模板默认min24/target36，AAB显式24/36。

工具使用私有staging和自包含无界面引擎，清理AI引用、保留CSV，签名只经进程环境传入，日志脱敏；Gradle缓存位于E盘。先校验私有输出再原子发布至dist，Windows恢复交付目录继承权限，失败半包留work。Windows导出工具只替换自身预设的模板路径，兼容新增Android预设。

## 三星安装

```powershell
& "D:/Unity/Editor/Data/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb.exe" -s R5CX211TXNT install --no-incremental -r "dist/Block-0.8.8-android-release.apk"
```

本机Unity旧ADB和Godot新版ADB会抢占5037端口，使用当前服务同版客户端即可；无需关闭编辑器或删除用户数据。首次交付曾在增量安装失败后回退streamed成功，后续显式 `--no-incremental` 可直接安装。本轮三星更新返回Success，设备版本为0.8.8(6)；录屏、截图及日志保存在本地 `work/menu-polish-20261020/`，不提交Git。最终安装base.apk与交付APK的SHA256均为 `a08b010cc52b318363b515964cadf03df3418398094568d4393a299d58fae0e8`，未卸载或清数据。最终游戏进程的有限日志观察未见脚本、fatal或多边形错误，不代表完整玩法验收。

## 待用户验收

- 不同于已检查三星桌面的其他启动器、圆形/圆角mask及用户对图案辨识度的最终确认；48px预览与真机截图仅核对显示，不等于Play审核通过。
- 手机三模式触控、特殊图案、竖屏布局/安全区、小屏适配。
- 系统返回、切后台、暂停、重开、声音与存档。
- Play Console实际上传、内部测试分发和审核。
