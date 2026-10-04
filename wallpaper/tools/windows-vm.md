# Windows 虚拟机测试环境（免费方案）

在 Apple 芯片 Mac 上用 **UTM + 微软官方 Windows 11 ARM64** 搭建壁纸的真实测试环境，全程免费。Windows 不激活也能正常用于测试（仅右下角有水印）。

已完成的准备（本机）：

- UTM 已安装：`/Applications/UTM.app`（含 `utmctl` 命令行）
- ISO 位置：`~/Downloads/Windows11_Client_arm64_zh-cn_26300_9457.iso`（简体中文 26H2，约 6.7 GB）
- 本机 24 GB 内存 / 12 核，推荐给虚拟机 **6–8 GB 内存、4 核、64 GB 磁盘**（磁盘按需增长，不立即占满）

## 一、创建虚拟机（约 10 次点击）

1. 打开 UTM → 点左上角 **「+」→ 「创建虚拟机」**
2. 选 **「Virtualize（虚拟化）」**——不要选 Emulate，Apple 芯片上原生虚拟化才有可用性能
3. 选 **「Windows」**
4. 勾选 **「Install Windows 10/11 using an ISO」**，点 "Browse" 选上面的 ISO；
   **同时勾选「Install drivers and SPICE tools」**（这是显卡驱动 + 共享工具，必勾）
5. 内存 6144–8192 MB，CPU 4 核，下一步
6. 磁盘 64 GB，下一步 → 命名（如 `Win11-测试`）→ 保存
7. 点 ▶ 启动，进入 Windows 安装程序

## 二、Windows 安装（主要是等待，约 20–40 分钟）

1. 语言/时间/键盘：默认（简体中文）→ 下一步
2. **「现在安装」** → 「我没有产品密钥」
3. 版本选 **「Windows 11 专业版」**（功能全；家庭版也行）
4. 接受条款 → **「自定义安装」** → 选中虚拟磁盘 → 下一步
5. 复制文件、多次重启后进入设置向导（OOBE）
6. 地区中国、键盘默认；**联网页**：虚拟机有网络（NAT），直接连 Wi-Fi 列表里任意网络或以太网即可
7. 账户：想用本地账户时，在网络页按 **Shift+F10** 打开命令行输入 `start ms-cxel:` 跳过联网，之后出现「域连接」离线账户选项；不折腾就用 Microsoft 账户登录（测试机无所谓）
8. 其余一律默认/「接受」进桌面

进桌面后如分辨率不对/卡：UTM 菜单栏图标 → 「Install SPICE Tools」重插一次驱动光盘，或在 VM 内打开「此电脑」里的 CD 驱动器运行 `spice-guest-tools` 安装程序后重启。

## 三、安装 Lively 并加载壁纸

VM 内（任选其一）：

```powershell
winget search lively          # 找到 Lively Wallpaper 后
winget install --id <上一条列出的ID> -e
```

或直接开 Microsoft Store 搜 **Lively Wallpaper** 安装（免费、开源，有 ARM64 支持）。

**把壁纸放进 VM，两种方式：**

- **方式 A（最快，不用传文件）**：Mac 上进入 `wallpaper/` 目录跑一个本地服务：
  ```sh
  cd ~/AiProjects/PondDesktop/wallpaper && python3 -m http.server 8000
  ```
  查 Mac 的局域网 IP（`ipconfig getifaddr en0`），在 Lively 里选「网址/Web address」壁纸，输入
  `http://<Mac的IP>:8000/index.html`
- **方式 B（共享文件夹）**：UTM → 虚拟机设置 → Sharing → 共享 `~/AiProjects/PondDesktop/wallpaper`（需 SPICE tools 已装），在 VM 的资源管理器网络位置里直接打开，把 `index.html` 拖进 Lively

## 四、测试清单（对照 README 的验证目标）

- [ ] 壁纸正常显示、30fps（对比 Mac `?stats=1` 的帧率量级）
- [ ] 光标扫过泛涟漪、急挥惊散、修饰键轻点投喂（Lively 设置里开启鼠标交互）
- [ ] 打开一个全屏应用（如 F11 的浏览器）→ 壁纸应暂停；切回桌面恢复
- [ ] 设置项（Lively 属性面板/URL 参数）切换主题、时段、鱼数生效
- [ ] 虚拟机窗口缩放/DPI 变化时布局自适应
- [ ] 长时间挂机（30 分钟+）无卡死、无内存暴涨

## 常见问题

- **Wallpaper Engine 在 ARM Windows 上未验证**：发布创意工坊前先在 Lively 过一遍；WE 需要的话用 x86 模拟方式（UTM 的 Emulate 模式性能差，不推荐）
- **VM 删不掉磁盘空间**：UTM 里删除 VM 后，`.utm` 包在 `~/Library/Containers/com.utmapp.UTM/Documents/` 一并清掉
- **ISO 下载链接过期**（24 小时）：重新打开浏览器访问 microsoft.com/en-us/software-download/windows11arm64 选语言再取链接
