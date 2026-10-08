# CommandDock

原生 macOS 键盘式应用启动器。单独按下并松开 Command，屏幕中央显示 MacBook 键盘布局；按对应物理键位或点击图标启动应用。

## 下载与安装

在本仓库的 **Releases** 页面下载 `CommandDock-版本号-universal.dmg`，打开后将 `CommandDock.app` 拖到「应用程序」。也可下载 ZIP，解压后把应用放到「应用程序」。

- **支持 Intel 和 Apple Silicon**：同一个安装包包含 `x86_64` 与 `arm64`，无需 Rosetta。
- **系统要求：macOS 13 Ventura 或更新版本**。
- 首次启动会显示设置窗口。前往「系统设置 → 隐私与安全性 → 辅助功能」，添加并启用 `/Applications/CommandDock.app`，然后回到软件点击「已授权，重新连接」。若仍无法连接，退出并重新打开应用。
- 发布包使用 **ad-hoc 签名，尚未经过 Apple Developer ID 签名与公证**。首次打开可能被 Gatekeeper 阻止；确认下载来自本仓库后，在「系统设置 → 隐私与安全性」中使用「仍要打开」。请勿关闭系统安全保护。企业受管设备可能不允许此类应用。
- 更新后若 macOS 要求重新授权，可在辅助功能列表移除旧条目，再添加新版应用。

## 使用

1. 单独按下并松开左或右 `⌘`，浮窗保持显示。默认最长按住时间为 0.5 秒，可在设置中调整。
2. 按已绑定按键或点击应用图标，启动或切换到应用，浮窗随即收起。
3. 按 `Esc`、再次单击 `⌘`、点击浮窗外部或点击关闭按钮，收起浮窗。
4. 点击菜单栏 `⌘` 图标 →「应用绑定与设置」，为数字、字母、标点或空格键选择应用。
5. 在设置中可暂停监听、设置登录时启动、导入 / 导出 JSON 绑定文件。恢复默认前会要求确认。

`⌘C`、`⌘V`、`⌘Tab`、`⌘Space` 等组合键不会触发浮窗。浮窗可见时按含修饰键的组合键会立即关闭浮窗，并将事件交还给原前台应用。未绑定的普通字符键在浮窗显示时被忽略，避免输入到后台窗口。

浮窗采用 **ANSI MacBook 物理键盘布局**，字母按物理键位定位，因此中文输入法下无需切换到英文。功能键、修饰键、Tab、Return、Delete、方向键保留系统用途。ISO / JIS 键盘额外键目前未展示；外接键盘可使用对应标准键位。安全输入模式（例如部分密码框）、锁屏以及 macOS 的安全限制可能暂停全局键盘事件。

默认绑定会按本机已安装应用生成，例如 Q → Safari、W → 邮件、E → Finder、R → 终端、T → 日历、S → 系统设置。跨电脑导入时优先使用 bundle identifier 查找应用；目标应用须先安装。

## 性能与隐私

- Swift、AppKit 和 SwiftUI 原生界面，无 Electron、WebView 或第三方运行时。
- 使用 Quartz 事件回调待命，没有周期轮询、动画循环或网络后台服务。
- 浮窗延迟创建并复用；应用图标按需缓存。
- 仅维护当前修饰键、按键和鼠标按住状态，不保存键盘输入、不读取窗口内容，也不上传数据。
- 绑定与偏好保存在本机 UserDefaults；仅用户主动导出时写入 JSON 文件。
- CPU、内存和能耗会随系统版本、显示状态及权限环境而变化，未承诺固定数值。

## 本地开发

需要 macOS 13+、Xcode / Command Line Tools 与 Swift 5.9+，无需下载第三方依赖。

```bash
swift test
./scripts/build.sh
```

`dist/` 中生成通用 `.app`、DMG、ZIP 和 `SHA256SUMS.txt`。构建脚本分别编译两个架构，再通过 `lipo` 合并并验证。测试覆盖单击 Command、左右 Command、系统快捷键、修饰键组合、长按、鼠标组合、已有按键按住、浮窗键盘事件及绑定文件解析。

可以通过 `VERSION`、`BUILD_NUMBER`、`OUT_DIR` 调整构建版本和输出目录；`SIGNING_IDENTITY` 默认为 ad-hoc。正式 Developer ID 分发还需自行配置签名、hardened runtime 与 Apple 公证，此流程不包含 Apple 证书或账号凭据。

## GitHub Actions

- 向 `main` 推送、提交 PR 或手动运行会执行测试，并生成可下载的构建产物。
- 测试分别在 `macos-15`（Apple Silicon）和 `macos-15-intel` 上运行。
- 推送 `v*` 标签（例如 `v1.0.0`）会自动构建并发布 GitHub Release，附带 DMG、ZIP 和校验和。
- 工作流默认只有读取权限，仅发布任务获得仓库内容写入权限。

```bash
git tag v1.0.0
git push origin v1.0.0
```

无 Developer ID 证书也能生成安装包；签名与权限说明见上方安装步骤。
