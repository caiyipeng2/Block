# 安装包图标

用户于2026-10-19要求搜索Block Blast图标，并将包体图标替换为相同图案。

- 官方页面：[Block Blast! / HungryStudio](https://play.google.com/store/apps/details?id=com.block.juggle&hl=en_US)。
- 图像源：`https://play-lh.googleusercontent.com/5FLR-EBlfNvoV9ydZkOMDqRF10nV64XcKdZzW_oQzmz2e8Me9PS5Zncnvviki0J3XumjO2a_lg6_IdwOqwnV=s512-rp`。
- `block-blast-official.png`：512×512 RGB，来自上述官方CDN的PNG字节，未重绘；SHA256 `8e1a2f6994b55f3414c0cbe8c3cb0e5cc168715922b64df4e0c83c03f92e0b9a`。
- 项目与Windows导出主图标、Android传统启动图标都使用此PNG。
- Android `adaptive-foreground.svg`：432×432透明图层，嵌入原PNG并等比放置于64..368区域。`adaptive-background.svg`为深蓝底，避免三星圆角/圆形mask大幅裁掉完整方块构图。
- 两个Android预设显式设置主图标、adaptive前景及背景，避免回退Godot默认机器人图标。未添加主题单色图标，保留用户要求的彩色图案。
- SVG导入已核对引擎实际纹理432×432、前景边界64..368，无损导入且未限制尺寸。

图标变更不修改包名、签名、游戏菜单、美术、玩法或存档。
