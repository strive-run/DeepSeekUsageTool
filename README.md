# DeepSeek Usage

macOS 菜单栏应用，登录 DeepSeek 账户后实时查看 API 用量、费用和 Token 消耗。

## 功能

- **菜单栏快捷查看** — 点击菜单栏图标，弹出面板展示用量概览
- **账户概览** — 卡片式展示账户余额、今日用量/今日费用、本月用量/本月费用
- **用量图表** — 费用 / Token / 请求三个指标图表同时竖排显示，展示本月每日趋势；每日柱按模型堆叠着色
- **统计数据** — 每张图表自动计算日均、峰值、活跃天数
- **数据获取** — 打开面板时自动拉取最新数据，也可随时点击菜单栏上的刷新按钮手动刷新

## 系统要求

- macOS 26.0 或更高版本
- Apple Silicon（arm64）或 Intel（x86_64）芯片均可
- Swift 6.2+（Xcode 或 CommandLineTools 均可，本项目在仅安装 CommandLineTools 的环境下构建验证通过）

## 如何构建

```bash
# 构建
swift build

# 运行（调试模式）
swift run DeepSeekUsage

# 构建 .app 包
make app
```

`make app` 会在 `.build/DeepSeek Usage.app` 生成可直接运行的应用程序包，将其拖入 `Applications` 文件夹即可使用。

其他可用的 make 目标：`make test`（运行测试）、`make clean`（清理构建产物）。

## 使用方法

1. 启动应用后，菜单栏会出现 DeepSeek 图标
2. 首次使用需要**登录 DeepSeek 账户**：
   - 左键点击菜单栏图标，点击「登录 DeepSeek」按钮
   - 或右键点击菜单栏图标，选择「登录」
3. 在弹出的登录窗口中完成 DeepSeek 账号登录
4. 登录成功后，用量面板会自动显示数据
5. 左键点击菜单栏图标随时查看用量（每次打开面板都会刷新数据）
6. 点击面板右上角刷新按钮可手动刷新
7. 右键点击菜单栏图标可退出应用

## 隐私说明

### 数据存储

- **登录凭据**：通过系统 WebView（WKWebView）的默认数据存储（`WKWebsiteDataStore.default()`）持久化保存。这是 macOS 系统内置的存储机制，凭据保存在当前用户的浏览器缓存中，不会以明文文件形式存放在应用目录下。
- **用量数据**：仅在内存中临时缓存，应用退出后即清除，不会写入磁盘。
- **不收集任何信息**：本应用**不会**向任何第三方服务器发送数据，所有网络请求仅用于与 DeepSeek 官方 API 通信。

### 工作原理

应用通过 WKWebView 打开 DeepSeek 官网用量页面，复用当前登录会话，从页面上下文读取登录令牌（Token），随后使用原生 URLSession 调用 DeepSeek 官方 API（`get_user_summary`、`usage/by_api_key/amount|cost`）获取账户余额、费用和用量数据。整个过程本质上是浏览器会话的复用，不涉及逆向工程或非公开接口。

### 网络通信

- 仅与 `platform.deepseek.com` 通信
- 所有请求均为 HTTPS 加密传输
- 请求中携带的 Authorization Token 仅用于 DeepSeek API 身份认证

## 项目结构

```
Sources/
  DeepSeekUsage/
    DeepSeekUsageMain.swift   # 应用入口
    AppState.swift            # 状态管理与刷新逻辑
    StatusBarController.swift # 菜单栏控制器
    Views.swift               # SwiftUI 面板视图
    Models.swift              # 数据模型
    DeepSeekWebSession.swift  # WebView 会话与 API 请求
    DeepSeekLogoPath.swift    # 图标路径
    LoginWindowController.swift # 登录窗口
    UsageAggregator.swift     # 用量数据聚合
Tests/
  DeepSeekUsageTests/         # 单元测试（Swift Testing）
Resources/
  AppIcon.icns                # 应用图标
Makefile                      # 构建/运行/app 打包
```

## 许可证

MIT License