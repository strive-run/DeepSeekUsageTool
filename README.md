# DeepSeek Usage

macOS 菜单栏应用，实时查看 DeepSeek API 用量、费用和 Token 消耗。

## 功能

- **菜单栏快捷查看** — 点击菜单栏图标，弹出面板展示用量概览
- **账户概览** — 实时显示账户余额、今日用量、本月费用
- **用量图表** — 柱状图展示本月每日的用量趋势，支持按费用 / Token / 请求数切换
- **模型细分** — 每日用量按模型拆分（deepseek-v4-flash、deepseek-v4-pro 等）
- **统计数据** — 自动计算日均、峰值、活跃天数
- **自动刷新** — 打开面板时自动拉取最新数据

## 系统要求

- macOS 26.0（Sequoia）或更高版本
- arm64（Apple Silicon，如 M1 / M2 / M3 / M4 系列芯片）

## 如何构建

确保已安装 Xcode 16 或更高版本（包含 Swift 6.2+）。

```bash
# 构建
swift build

# 运行（调试模式）
swift run DeepSeekUsage

# 构建 .app 包
make app
```

构建完成后，`make app` 会在 `.build/DeepSeek Usage.app` 生成可直接运行的应用程序包，将其拖入 `Applications` 文件夹即可使用。

## 使用方法

1. 启动应用后，菜单栏会出现 DeepSeek 图标
2. 首次使用需要**登录 DeepSeek 账户**：
   - 左键点击菜单栏图标，点击「登录 DeepSeek」按钮
   - 或右键点击菜单栏图标，选择「登录」
3. 在弹出的登录窗口中完成 DeepSeek 账号登录
4. 登录成功后，用量面板会自动显示数据
5. 左键点击菜单栏图标随时查看用量
6. 右键点击菜单栏图标可退出应用

## 隐私说明

### 数据存储

- **登录凭据**：通过系统 WebView（WKWebView）的默认数据存储（`WKWebsiteDataStore.default()`）持久化保存。这是 macOS 系统内置的存储机制，凭据保存在当前用户的浏览器缓存中，不会以明文文件形式存放在应用目录下。
- **用量数据**：仅在内存中临时缓存，应用退出后即清除，不会写入磁盘。
- **不收集任何信息**：本应用**不会**向任何第三方服务器发送数据，所有网络请求仅用于与 DeepSeek 官方 API 通信。

### 工作原理

应用通过 WKWebView 打开 DeepSeek 官网用量页面，自动捕获当前登录会话的 Authorization 令牌（Token），然后用该令牌调用 DeepSeek 官方 API 获取费用和用量数据。整个过程本质上是浏览器会话的复用，不涉及逆向工程或非公开接口。

### 网络通信

- 仅与 `platform.deepseek.com` 通信
- 所有请求均为 HTTPS 加密传输
- 请求中携带的 Authorization Token 仅用于 DeepSeek API 身份认证

## 项目结构

```
Sources/
  DeepSeekUsage/
    DeepSeekUsageMain.swift   # 应用入口
    AppState.swift            # 状态管理
    StatusBarController.swift # 菜单栏控制器
    Views.swift               # SwiftUI 面板视图
    Models.swift              # 数据模型
    DeepSeekWebSession.swift  # WebView 会话管理
    DeepSeekLogoPath.swift    # SVG 图标路径
    LoginWindowController.swift # 登录窗口
    UsageAggregator.swift     # 用量数据聚合
Resources/
  AppIcon.icns                # 应用图标
```

## 许可证

MIT License
