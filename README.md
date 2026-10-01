# 一池 / Yichi 1.2

原生 macOS 金鱼动态桌面。AppKit 负责桌面窗口和菜单栏，SpriteKit 负责鱼群动画，SwiftUI 负责中文控制面板。纯色、透明图形与细颗粒材质构成画面，不使用渐变色。无联网行为、第三方依赖或个人文件访问。

## 本次更新

- 新增菜单栏融合：开启桌面池塘时临时将系统壁纸替换为与池水一致的纯色，顶部菜单栏随池水主题变色；关闭、退出或切换主题时自动恢复原壁纸及其显示选项。
- 视野默认拉远到 1.65 倍，可在 1–2.4 倍间调节。鱼、植物、水波及投喂位置使用一致的世界坐标。
- 池底加入不规则淤泥、砂砾、卵石、细颗粒和水光线条。
- 池边增加荷叶、荷花、莲蓬、莲藕根茎、沉水茎、带状水草、金鱼藻和浮萍；植物丰茂度可调。
- 新增单尾金鱼画室：鱼身色、鱼鳍色、名称、45%–200% 大小、自由画笔、橡皮、笔刷粗细、起始花纹、撤销、重做、清空和恢复。
- 每尾金鱼的外观自动保存并同步到所有桌面和预览，调整鱼群数量后仍保留对应金鱼的设计。

## 构建与运行

需要 macOS 13 以上及 Apple Command Line Tools。

```sh
./build.sh
open build/一池.app
```

`build/一池.app` 包含 arm64 和 x86_64 两种架构。也可指定输出目录：

```sh
./build.sh /absolute/path/to/output
```

构建采用本地签名；向其他电脑公开分发时，需另外配置 Apple Developer ID 签名与公证。

## 使用

通过菜单栏金鱼图标控制桌面；从“金鱼画室”进入编辑器，选择左侧金鱼，在中间鱼身上拖动绘制。修改会自动保存，点击“回到池塘”返回预览。更改鱼身或鱼鳍颜色时，点颜色方块展开纯色色板；也可输入六位十六进制色号选择任意颜色。

快捷键：⌘1 池塘预览，⌘2 金鱼画室，⌘, 设置，⌘Q 退出。绘制画布获得焦点时，⌘Z 撤销、⇧⌘Z 重做。真实桌面不拦截鼠标；桌面投喂通过菜单栏完成，预览可直接点水面。

配置保存在本机 UserDefaults，键包含 `fishCount`、`swimSpeed`、`waterTheme`、`desktopEnabled`、`lowPower`、`viewDistance`、`plantDensity`、`menuBarHarmony` 和 `fishDesigns`。画室从旧版本配置自动补充默认值，不会清除已有设置。

## 验证

```sh
build/一池.app/Contents/MacOS/PondDesktop --self-test
build/一池.app/Contents/MacOS/PondDesktop --render-preview /absolute/path/to/pond.png
```

自检使用独立偏好域，不修改真实鱼群外观。它验证 60 尾鱼在 3 档速度及 3 种屏幕尺寸下连续模拟 60 秒的边界、有限值和转向速度，以及暂停恢复、投喂、单尾外观持久化、画笔裁切、橡皮恢复底色、撤销重做、鱼群纹理更新、相机缩放、零尺寸窗口保护及纯色壁纸文件生成。

## 源码结构

- `Sources/Pond.swift`：设置、鱼群运动、世界坐标与桌面/预览窗口。
- `Sources/WallpaperSync.swift`：菜单栏融合用的纯色壁纸生成与原壁纸保存/恢复。
- `Sources/FishArtwork.swift`：金鱼外观数据、笔画数据、材质绘制及鱼鳍动画。
- `Sources/FishEditor.swift`：单尾编辑器、画布输入、撤销重做及自动保存。
- `Sources/PondEnvironment.swift`：池底和水生植物的程序化绘制。
- `Sources/Checks.swift`：外观编辑及缩放回归检查。
- `Sources/main.swift`：应用入口。

静态景物和鱼身缓存为纹理；运行时更新鱼的位置和鳍的旋转。默认 30 fps，节能模式 20 fps，休眠和会话切换时暂停。桌面窗口处于系统桌面图层上方、图标下方，忽略鼠标。macOS 菜单栏的半透明底色只取样系统壁纸、不含桌面图层窗口，因此“菜单栏融合”通过临时替换纯色壁纸实现：纯色文件保存在 `~/Library/Application Support/一池/`，原壁纸路径与显示选项按屏幕记录在 `savedWallpapers`，关闭桌面、关闭融合或退出应用时恢复；切换主题会即时换用新水色。

## 验证范围

Apple 芯片 / macOS 15.5 已运行验证；Intel 版本已编译，未在 Intel 硬件上测试。多屏实现保留，仍需更多硬件验证。植物和水底采用带材质细节的绘制风格；不是实拍背景。macOS 桌面层级行为需随系统升级验证。
