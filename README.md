# CommandDock

原生 macOS 键盘式应用启动器。单独按下并松开 Command，屏幕中央显示 MacBook 键盘布局；按对应物理键位或点击图标启动应用。

## 下载与安装

在本仓库的 **Releases** 页面下载 `CommandDock-版本号-universal.dmg`，打开后将 `CommandDock.app` 拖到「应用程序」。也可下载 ZIP，解压后把应用放到「应用程序」。

- **支持 Intel 和 Apple Silicon**：同一个安装包包含 `x86_64` 与 `arm64`，无需 Rosetta。
- **系统要求：macOS 13 Ventura 或更新版本**。
- 首次启动会显示设置窗口。前往「系统设置 → 隐私与安全性 → 辅助功能」，添加并启用 `/Applications/CommandDock.app`，然后回到软件点击「重新连接」。若仍无法连接，退出并重新打开应用。
- 发布包使用 **ad-hoc 签名，尚未经过 Apple Developer ID 签名与公证**。首次打开可能被 Gatekeeper 阻止；确认下载来自本仓库后，在「系统设置 → 隐私与安全性」中使用「仍要打开」。请勿关闭系统安全保护。企业受管设备可能不允许此类应用。
- 更新后若 macOS 要求重新授权，可在辅助功能列表移除旧条目，再添加新版应用。

### 提示「没有响应」或无法打开

未公证的下载包可能被 macOS 在进入应用代码前拦截，留下无法响应的启动进程。先在「活动监视器」结束 CommandDock，再到「系统设置 → 隐私与安全性」允许打开，然后重新启动。

如果仍提示「没有响应」，且已确认安装包来自本仓库、SHA256 与 Release 中的 `SHA256SUMS.txt` 一致，可在终端执行以下命令。仅移除这个应用的下载隔离标记，不关闭系统 Gatekeeper：

```bash
pkill -x CommandDock
xattr -dr com.apple.quarantine /Applications/CommandDock.app
open /Applications/CommandDock.app
```

此操作只适用于已核验来源的未公证包；正式分发应使用下方的 Developer ID 签名与公证流程。

## 从 1.0.0 升级 / 键盘无响应

1. 先通过菜单栏退出旧版，再替换「应用程序」中的 CommandDock。
2. 新版设置会显示真实的全局键盘连接结果。点击「启用全局快捷键」可发起系统授权请求。
3. 如果系统开关已打开，但软件仍提示未连接，移除辅助功能列表里的旧 CommandDock 条目，再通过「+」添加 `/Applications/CommandDock.app` 并开启，然后退出软件并重新启动。ad-hoc 签名会随构建变化，旧授权记录可能不再匹配新版。
4. 授权成功后，关闭设置窗口或切换到其他应用，再单独按下并松开 Command。

浮窗现在能接收本地键盘事件；即使全局授权尚未生效，通过菜单栏手动显示浮窗后，也可以按绑定键启动应用。全局 Command 呼出仍须系统授权。设置窗口正在接收键盘输入时暂停 Command 触发；设置在后台时不再阻止触发。

## 使用

1. 单独按下并松开左或右 `⌘`，浮窗保持显示。默认最长按住时间为 0.5 秒，可在设置中调整。
2. 按已绑定按键或点击应用图标，启动或切换到应用，浮窗随即收起。
3. 按 `Esc`、再次单击 `⌘`、点击浮窗外部或点击关闭按钮，收起浮窗。
4. 点击菜单栏 `⌘` 图标 →「应用绑定与设置」，为数字、字母、标点或空格键选择应用。
5. 在设置中可暂停监听、设置登录时启动、导入 / 导出 JSON 绑定文件。恢复默认前会要求确认。

`⌘C`、`⌘V`、`⌘Tab`、`⌘Space` 等组合键不会触发浮窗。浮窗可见时，修饰键按下即收起浮窗并恢复原应用的键盘焦点，让接下来的组合快捷键交给系统。未绑定的普通字符键在浮窗显示时被忽略，避免输入到后台窗口。

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

可以通过 `VERSION`、`BUILD_NUMBER`、`OUT_DIR` 调整构建版本和输出目录；`SIGNING_IDENTITY` 默认为 ad-hoc。指定 Developer ID 身份时会启用 hardened runtime 和安全时间戳。设置 `NOTARIZE=1` 并提供 `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` 后，脚本会公证应用、附加公证票据、验证 Gatekeeper，再重新生成 ZIP；DMG 也会签名、公证和附加票据。公证失败会停止打包。

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

### 配置正式签名与公证

在仓库的 Settings → Secrets and variables → Actions 配置以下 Secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 含私钥的 Developer ID Application `.p12` 证书，经过 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 的导出密码 |
| `MACOS_SIGNING_IDENTITY` | 完整身份名称，例如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple 开发者账号邮箱 |
| `APPLE_TEAM_ID` | 开发者团队 ID |
| `APPLE_APP_PASSWORD` | Apple 账号生成的应用专用密码 |

需要 Apple Developer Program 的 Developer ID Application 证书；Apple Development 证书不能用于此分发公证。配置后重新运行流水线或发布新版本，旧下载包不会自动变成已公证包。PR 构建保持 ad-hoc；未配置证书时流水线会明确警告，配置了证书但缺少其他凭据时会失败，避免静默回退。证书导入临时钥匙串，任务结束时清理。
