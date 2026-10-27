# UI 图生成说明

日期：2026-10-26。用途：用户确认前的最终 UI 提案，未接入游戏。

生成方式：Codex 内置 ImageGen。三张图都使用现有菜单/设置真机图作为美术参考；入口/状态图额外参考第一张榜单提案。原生成文件保留在 Codex 生成目录，提案副本位于当前目录。

## 三榜主界面提示词

```text
Use case: ui-mockup. Create a polished final UI proposal board for the existing Chinese casual block puzzle mobile game Block. This is a design approval artifact, not an implemented screenshot. Use the two referenced images ONLY as style references: reference 1 is the actual game main menu, reference 2 is its actual settings panel. Keep the game's restrained dimensional blue casual-game style, medium royal blue outer panels, deep indigo inset list areas, light blue rim highlight, white readable Chinese type, gold trophy, simple bevels and clean contact shadows. Preserve its coherent friendly casual 3D style. Do not invent a different brand, rounded candy world, glassmorphism or neon sci-fi UI.
Output one high resolution wide board, around 2400x1800, containing THREE large straight-on portrait mobile screens, side by side, all equal size, with generous 32px gutters. No phone devices, no hands, no perspective. Very large, clean, carefully written Simplified Chinese UI. Board background dark navy. Small external heading "全球排行榜 · UI 定稿提案" and tiny external footer "示例数据 · 供确认".
All three screens share the exact same layout:
Top safe margin. Back arrow left, gold trophy next to centered title "排行榜", info icon right. Three equally wide mode tabs "闯关" "经典" "自由". Under tabs, subtle centered label "全球 · 总榜". Compact top 3 podium: second place left with silver accents, first place taller in center with gold crown and warm gold accents, third place right with bronze accents. Each top three player has a simple block-shaped mascot avatar, name, rank number, and a legible score label. Use generic geometric puzzle avatars, no photos, no flags. Below podium a navy list card showing header, then ranks 4,5,6,7 with aligned columns, clear compact row dividers. Bottom of every screen has a fixed highlighted personal row with rank, cyan outline, avatar, text "我 · 玩家4821", and record. Below a large beveled green CTA, then tiny safe-area margin.
LEFT screen: adventure selected tab GOLD, other tabs subdued blue. Metric line "先比通关数，再比总积分". Podium: first "方块王者" with "96关" and "268,540分"; second "青柠方块" with "96关" and "251,800分"; third "星光" with "95关" and "260,000分". List columns "名次" "玩家" "通关 / 总积分". Row4 "晨星" "94关 / 242,120"; row5 "小满" "92关 / 231,640"; row6 "积木熊" "90关 / 226,330"; row7 "七喜" "89关 / 224,180". Personal row rank "127", "我 · 玩家4821", "42关 / 83,640". Green CTA "继续闯关".
MIDDLE screen: classic tab selected GREEN. Metric line "单局最高分". Podium first "方块王者" "186,420"; second "青柠方块" "174,860"; third "星光" "169,230". List headers "名次" "玩家" "最高分". Row4 "晨星" "156,800"; row5 "小满" "148,620"; row6 "积木熊" "139,540"; row7 "七喜" "134,180". Personal rank "127", "我 · 玩家4821", "14,580". Green CTA "再来一局".
RIGHT screen: free tab selected PURPLE. Metric line "单局最高分". Podium first "青柠方块" "214,680"; second "方块王者" "203,540"; third "星光" "198,320". List headers "名次" "玩家" "最高分". Row4 "小满" "186,420"; row5 "晨星" "175,680"; row6 "七喜" "169,240"; row7 "积木熊" "162,300". Personal rank "168", "我 · 玩家4821", "18,620". Green CTA "再来一局".
Make rank 1/2/3 numbers clearly visible and use normal row rank numbers for 4-7. Exact metric distinction between adventure and score modes is essential. Main ranking content must be sharp and aligned, no text overlaps. Every touch control generously sized. No weekly tab, no rewards, no coin currency, no global chat, no extra menus. A tasteful compact leaderboard for a shipped game with readable text, not a marketing poster.
```

## 入口与状态提示词

```text
Use case: ui-mockup. Create a second polished UI approval board for the same Block mobile puzzle game. Inputs: image1 actual main menu for visual style and layout; image2 the approved-proposal leaderboard board for consistent blue beveled panels and block avatars; image3 actual settings panel for the familiar dimensional blue card material. These are references, not literal flat textures to paste. Output one wide high-resolution board around 2400x1800, three equal straight-on portrait screens side by side on navy background, no devices, no perspective, no hands. Heading above "排行榜 · 入口与状态提案". Label below each phone-size screen respectively "主菜单入口" / "成绩结算" / "离线与待同步". Tiny footer "示例数据 · 供确认". Clean readable accurate Chinese.
LEFT: Keep the actual main menu's blue gradient, original BLOCK BLAST crown logo, three dimensional wide buttons gold "闯关模式" with white location pin, green "经典模式" with white infinity, purple "自由模式" with white puzzle piece, and modest blue bottom "退出游戏". Keep top right settings gear. Only ADD a same-sized top LEFT gold trophy button, with the small label "排行榜" directly under it, symmetrical with top-right gear. Keep highest-score plate "最高分 2300" below the logo. Do not alter original mode titles/order/palette.
MIDDLE: Classic mode finished-game screen on dimmed blue block puzzle grid background. Center a familiar blue beveled modal, white text title "游戏结束", small "本局得分", large white numeric score "14,580", gold short line "新纪录！", small cyan trophy rank capsule "全球第127名". Below a medium blue secondary action button "查看排行榜". Green primary CTA "再来一局". Quiet lower action "返回菜单". Keep clear visual hierarchy: score largest, ranking secondary. No currency, no rewards, no extra stats, no monetization. Ranking is a returned sample server result, not estimated.
RIGHT: The exact classic leaderboard layout from reference2: header trophy+排行榜, three tabs 闯关/经典/自由 with classic green selected, compact top3 podium, navy 4-7 list, personal sticky row. Add an amber top status bar just below tabs reading "离线 · 显示上次排名" with a small clear retry control "重试" at right. Subtle caption "上次更新 10:24". Top3 186,420 /174,860/169,230 scores. Rows4-7 same pattern as reference. Personal row rank127 and "我 · 玩家4821", synced score "14,580", and under this row a slim amber message "新纪录15,200待同步". Bottom primary green CTA "再来一局" still available. Pending new record is NEVER paired with a fake new rank. Avoid spinners replacing whole content, no screen-blocking error modal, no white generic settings interface.
Keep the style restrained and implementable: royal blue outer card, indigo list, light blue highlight rim, gold trophy, bevel shadows, comfortable spacing, large text, simple friendly block avatars. Exact Chinese, aligned readable typography. No unrelated screens.
```

图中玩家、排名及成绩均为示例，不代表真实联网数据。

## Google 绑定设置页提示词

```text
Create one high-resolution portrait mobile UI proposal screen for the existing Block casual block puzzle game settings page. Use the attached actual settings screenshot only as a style reference. Preserve the existing visual language: royal blue outer rounded panel, deep indigo inner card, pale blue rim, white icons and Chinese text, green beveled action buttons, large touch-friendly controls, dark blue game menu dimmed behind. No device frame, no perspective, straight-on.
Screen title at top: "设置". Keep the existing three top toggles in one row: "音效", "背景音乐", "画面震动", each with simple white vector icon and small status "已开启". Keep the "减少动画" toggle row and a horizontal separator.
Add a new account section below the animation setting, with section label "设备账号". Inside a compact indigo panel: an abstract blue block avatar, bold name "玩家4821", small status line "设备账号已启用", a subtle line "UID 已生成 · 本机存档正常保存", and a prominent blue secondary button labeled exactly "绑定 Google 账号" with a small simple Google-style multicolor G mark. Under the button, small readable helper text: "绑定后可上传存档并在新设备恢复". Include a small secondary text action "以后再说" aligned right, not dominant. Keep existing green buttons below: "返回菜单", "试听音效", "退出游戏"; fit the new account section by making the card vertically scrollable, not by shrinking touch targets.
Use accurate Simplified Chinese, no guest wording, no raw device ID, no email address, no phone number, no coins, no ads. This is a UI approval mockup, not implementation.
```

## 入口图定稿调整

最终交付使用 `02-entry-results-offline-v2.png`，将菜单模式按钮收回既有约 66% 屏宽，原稿保留供对比。

```text
Edit target: image1 is an existing UI proposal board with three screens. Image2 is the actual original main menu. Make ONE precise layout correction only in the LEFT screen of image1. Preserve ALL text, title, footer, center result screen and right offline leaderboard screen pixel-for-pixel in visual design; do not rewrite them. LEFT main menu: match the original menu's spacious proportional layout from image2. The three gold/green/purple mode buttons must be about 66 percent of the width of the left screen (currently too wide, about 85 percent), centered, all identical width, and height about one quarter of their width. Keep their existing exact labels 闯关模式 / 经典模式 / 自由模式 and icons. Best-score plate width about 66 percent and centered. Keep logo proportional and preserve the new gold trophy button at top-left and settings gear at top-right. Keep exit button smaller and centered near bottom. Do not stretch screen or change the board dimensions, center/right screens or score numbers. This is existing Block casual game blue art with simple beveled buttons, no added decoration. Preserve all Simplified Chinese labels accurately.
```
