# 一池 · 网页壁纸（Windows / Wallpaper Engine / Lively）

macOS 原生动态桌面「一池」的网页版。一个自包含的 HTML5 Canvas 壁纸，无任何图片与网络请求，池塘全部程序化绘制；模拟常数、随机种子与绘制路径逐项移植自 `Sources/`，与 Mac 版布局一致。

## 安装

**Wallpaper Engine（Steam）**

1. 打开 Wallpaper Engine → 「安装壁纸」→ 「打开壁纸编辑器」；
2. 选择「创建壁纸」→ 类型选 **网页壁纸** → 选择本 `wallpaper/` 文件夹（`index.html` 所在目录）；
3. 或不开编辑器：WE 主界面「从文件安装」直接选 `index.html`。

**Lively Wallpaper（免费）**

把 `wallpaper/index.html`（或整个文件夹）直接拖进 Lively 窗口即可。

**普通浏览器预览**

直接打开 `index.html`。支持 URL 参数调试：

```
index.html?theme=ink&fish=12&speed=1.2&distance=1.65&density=1.15&daylight=night&feed=alt&mouse=off&t=2
```

| 参数 | 取值 | 说明 |
|---|---|---|
| `theme` | jade / ink / blue | 青池 / 墨池 / 晴池 |
| `fish` | 6–60 | 金鱼数量 |
| `speed` | 0.3–1.8 | 游动速度 |
| `distance` | 1.0–2.4 | 视野远近（越大越远） |
| `density` | 0.5–1.8 | 植物丰茂度 |
| `daylight` | auto / dawn / noon / dusk / night | 时间光线 |
| `feed` | alt / ctrl / shift / none | 投喂修饰键 |
| `mouse` | off | 关闭鼠标互动 |
| `t` | 秒数 | 预走模拟（截图用） |
| `freeze` | 任意值 | 渲染一帧后停止动画循环（测试脚本截图用，秒级出图） |

## 交互（与 Mac 版一致）

- 光标缓缓拂过水面泛起涟漪，附近金鱼好奇靠近、游近停驻端详；
- 快速挥动光标惊散鱼群（0.6 秒内只触发一次）；
- 按住修饰键（默认 Alt，可在壁纸属性里换）轻点桌面空白处投喂，饲料 16 秒消散，最多 5 处并存；
- 时间光线默认跟随本地时钟（4–10 凌晨、11–16 中午、17–19 傍晚、其余晚上），也可在壁纸属性里固定。

在 Wallpaper Engine 中需要开启「允许壁纸与鼠标交互」才能收到点击；光标位置由 `wallpaperRegisterMousemoveListener` 全局转发，无需桌面获得焦点。

## 发布到 Steam 创意工坊

1. 用 Wallpaper Engine 编辑器打开本文件夹（网页壁纸类型）；
2. `preview.gif` 已在根目录（需动图或视频作为预览，可用 `tools/make-preview.sh` 重新生成）；
3. 编辑器内填写标题与描述 → 「创意工坊」→ 「上传」，首次上传用 `visibility: private` 自测，确认后改公开；
4. `project.json` 的 `general.properties` 定义了用户属性（主题/数量/速度/视野/丰茂度/时段/互动/投喂/节能），会显示在 WE 的壁纸设置面板里。

## 在 Mac 上测试（无需 Windows）

**一键回归**：`./tools/test.sh` 依次跑语法检查、`?selftest=1` 功能自检、`?drive=1` 交互场景、`?soak=1800` 长跑浸泡、6 组截图矩阵（默认/夜景/墨池傍晚/带鱼屏/Retina/高密度）与金基准的逐张 PSNR 对比；确定性渲染下应全部 inf。首次或有意改动画后先 `./tools/test.sh --save-baseline` 重存基准。

手动模式（都是 URL 参数，浏览器打开即可）：

| 参数 | 作用 |
|---|---|
| `?selftest=1` | 断言鱼群边界/转向、投喂并存上限、涟漪节流、惊散冷却、时段映射、坐标换算 |
| `?drive=1` | 模拟 Wallpaper Engine 协议（`wallpaperRegisterMousemoveListener` / `applyUserProperties`）端到端验证：缓动涟漪、急挥惊散、修饰键投喂落点、属性变更生效 |
| `?soak=1800` | 快进 30 分钟模拟，检查有限值、涟漪/碎屑/投喂点上限、反光稳定（不渲染，秒级完成） |
| `?stats=1` | 帧率 HUD：fps、update/render 毫秒、实体计数。窗口拉到 4K 尺寸验证性能 |
| `?clock=23` | 固定"当前时间"验证自动时段 |
| `?t=120` | 预走 2 分钟再显示，检查任意时刻的首帧表现 |

进阶：

- **CPU 降速模拟低端 Windows**：Chrome DevTools → Performance → CPU 4×/6× 降速后看 `?stats=1` 是否仍 ≥30fps；
- **多窗口多屏**：开两个不同尺寸窗口并排，对应 WE 每屏一个壁纸实例的形态；
- **终极验证**：Parallels/UTM 装 Windows + Lively（免费，有 ARM64 版）拖入 `index.html`，在真实的 WorkerW/WebView2 环境里跑；Wallpaper Engine 在 ARM Windows 上兼容性未验证，建议上传创意工坊前先在 Lively 里过一遍。完整搭建步骤见 [`tools/windows-vm.md`](tools/windows-vm.md)。

## 与 macOS 版的差异（v0.1）

- 小乌龟、蝌蚪、田螺与蝴蝶飞鸟访客尚未移植（对应 `pondCritters` / `pondVisitors`）；
- 金鱼画室（自定义外观）尚未移植，鱼群使用四套预设外观；
- 池底折射以横条平移近似（SpriteKit 用着色器逐像素位移），涟漪波前同样影响池底；
- 全屏暂停、帧率限制、多屏实例由 Wallpaper Engine / Lively 负责。

## 源码结构

| 文件 | 内容 |
|---|---|
| `js/lib.js` | 确定性随机（与 Swift 同种子）、色彩、时段光色、调色板 |
| `js/art.js` | 鱼身/鱼尾/鱼鳍、六类植物、波纹与反光纹理的程序化烘焙 |
| `js/bed.js` | 池底烘焙与植物群落布局（PondEnvironment.swift 移植） |
| `js/sim.js` | 鱼群运动学、光标意图流、涟漪与反光（Swimmer/CursorStream/PondWater 移植） |
| `js/pond.js` | 场景编排、相机、图层、渲染循环与 WE/Lively/浏览器集成 |
| `project.json` | Wallpaper Engine 工程描述与用户属性 |
| `tools/make-preview.sh` | 无头 Chrome 截帧 + ffmpeg 生成 preview.gif |
