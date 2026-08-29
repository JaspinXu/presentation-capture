# MacBook 上从零运行 iOS 版

这份说明面向第一次使用 MacBook、Xcode 和 Flutter 的开发者。目标是先在 iPhone Simulator 中看到并操作应用 UI，再转到真实 iPhone 验证摄像头、麦克风、4K 和后台上传。

## 1. 需要安装什么

必须安装：

1. **Xcode**：从 Mac App Store 安装，用于 iOS 编译、模拟器和真机签名。安装最新正式版，不要先装 beta 版。
2. **Flutter stable SDK**：本项目的主要开发工具链。
3. **Visual Studio Code**：推荐用于修改 Dart/Flutter 代码；安装其中的 Flutter 扩展时会同时安装 Dart 扩展。

按需要安装：

- **Docker Desktop for Mac**：推荐，用来在 Mac 本机启动演示登录和视频上传服务器。
- **GitHub Desktop**：如果暂时不熟悉 Git 命令，可用它登录 GitHub 并克隆 private repository。
- **CocoaPods**：当前项目使用 Flutter 的 Swift Package Manager，不需要为了第一次运行专门安装。以后某个新增插件只支持 CocoaPods，或者 `flutter doctor` 明确提示时再安装。

不需要安装 Android Studio，也不需要先购买 Apple Developer Program。iOS 模拟器不需要代码签名；配置正式 Apple 登录、真机长期分发和 TestFlight 时才需要进一步处理开发者团队和证书。

建议至少预留 40 GB 可用空间，因为 Xcode、iOS Simulator runtime、Flutter SDK 和编译缓存都会占用空间。

官方参考：[Flutter iOS 环境设置](https://docs.flutter.dev/get-started/install/macos/mobile-ios)、[Apple 安装 Xcode 和 Simulator](https://developer.apple.com/documentation/safari-developer-tools/installing-xcode-and-simulators)、[Xcode 系统要求](https://developer.apple.com/xcode/system-requirements)。

## 2. 首次配置 Xcode

1. 先在 **系统设置 > 通用 > 软件更新** 中更新 macOS，确保它支持当前正式版 Xcode。
2. 从 Mac App Store 安装并打开 Xcode。
3. 接受许可协议，让 Xcode 完成首次组件安装。
4. 在 Xcode 的 **Settings > Components** 中确认至少安装一个 iOS Simulator runtime。也可在 Terminal 下载：

```bash
xcodebuild -downloadPlatform iOS
```

5. 在 Terminal 执行：

```bash
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
sudo xcodebuild -license
```

第二条命令显示协议时，阅读后输入 `agree`。如果你的 Mac 是 M1/M2/M3/M4 等 Apple silicon，可安装 Rosetta 以兼容少数工具：

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```

## 3. 安装 Flutter

推荐把开发文件放在自己的 `~/Developer` 目录：

```bash
mkdir -p ~/Developer
git clone https://github.com/flutter/flutter.git --branch stable ~/Developer/flutter
echo 'export PATH="$HOME/Developer/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
flutter --version
flutter doctor -v
```

`flutter doctor -v` 的 Xcode 项应为绿色。Android toolchain 的警告目前可以忽略，因为当前只开发 iOS。

也可以在 VS Code 中安装 **Flutter** 扩展后，使用 Command Palette 中的 Flutter SDK 下载功能；两种方式选择一种即可，不要重复安装多份 Flutter。

## 4. 从 GitHub 获取本项目

在 Terminal 执行：

```bash
cd ~/Developer
git clone https://github.com/JaspinXu/presentation-capture.git
cd presentation-capture
git switch main
git pull origin main
flutter config --enable-swift-package-manager
flutter pub get
```

因为仓库是 private，GitHub 可能打开浏览器要求登录。如果命令行认证不熟悉，可以用 GitHub Desktop 登录后选择 **File > Clone Repository**，并把项目放到 `~/Developer/presentation-capture`。

运行项目自带检查：

```bash
cd ~/Developer/presentation-capture
./tool/verify_macos.sh
```

## 5. 启动本地服务器

要使用演示账号进入主页并测试上传，需要先启动服务器。安装并打开 Docker Desktop，然后新开一个 Terminal：

```bash
cd ~/Developer/presentation-capture/server
docker compose up --build
```

看到服务器监听 `8080` 后保持这个窗口运行。模拟器中的服务器地址使用：

```text
http://localhost:8080
```

演示账号：

```text
demo@nus.edu.sg
demo1234
```

停止服务器时在该 Terminal 按 `Control + C`。不想安装 Docker 时，也可安装 Node.js 22，然后在 `server` 目录运行 `npm install` 和 `npm start`。

## 6. 最快看到 iPhone 模拟器 UI

先启动 Simulator：

```bash
open -a Simulator
```

再开一个 Terminal：

```bash
cd ~/Developer/presentation-capture
flutter devices
flutter run
```

如果同时列出了多个设备，复制 `flutter devices` 中某个 iPhone Simulator 的 device ID，然后运行：

```bash
flutter run -d DEVICE_ID
```

第一次构建会下载和编译插件，等待时间较长是正常的。应用出现后，用演示账号登录，即可检查登录、语言切换、主页、视频列表、设置、720p/1080p/4K 选择和表单 UI。

应用运行期间，在 Terminal 中：

```text
r  热重载：普通 Dart/UI 修改后使用
R  热重启：初始化或状态不正确时使用
q  停止应用
```

## 7. 完全通过 Xcode UI 运行

必须先执行一次 `flutter pub get`，然后运行：

```bash
cd ~/Developer/presentation-capture
open ios/Runner.xcworkspace
```

注意打开的是 `Runner.xcworkspace`，不是 `Runner.xcodeproj`。

在 Xcode 顶部：

1. Scheme 选择 **Runner**。
2. Run Destination 选择一个 iPhone Simulator，例如当前可用的 iPhone Pro 型号。
3. 点击左上角三角形 **Run**，或者按 `Command + R`。
4. 等待 Build Succeeded，Simulator 会自动打开并安装应用。
5. 底部 Debug Console 可查看 Swift、Flutter 插件及网络错误。

模拟器编译不需要在 **Signing & Capabilities** 中选择 Team。如果 Xcode 显示 Flutter 生成包不存在，关闭 Xcode，在项目根目录重新运行 `flutter pub get`，再打开 workspace。

## 8. 模拟器能验证和不能验证的内容

模拟器适合验证：

- 中英文 UI、布局、导航和表单
- 演示账号登录和本地服务器连接
- 设置持久化和本地数据库的普通流程
- 不依赖真实摄像头的视频列表与上传状态界面

模拟器不能作为以下功能的最终验收：

- 后置摄像头实际录制、麦克风音质和音画同步
- 720p、1080p、4K 的真实编码能力
- 录制暂停/继续后生成 MP4 的兼容性
- 锁屏、切后台、断网后的 iOS background URLSession 行为
- 长时间 4K 录制的发热、电量和存储消耗

这些必须在真实 iPhone 上测试。模拟器没有可用摄像头时，进入录制页显示“无法打开摄像头”不代表真机代码失败。

## 9. 下一步连接真实 iPhone

1. 用数据线连接 iPhone，在 Mac 和 iPhone 上选择信任。
2. Xcode 打开 **Settings > Accounts**，添加 Apple Account。
3. 打开 `Runner.xcworkspace`，选择 Runner target 的 **Signing & Capabilities**，选择你的 Team。
4. 将 Run Destination 改为你的 iPhone。
5. 在 iPhone 的 **设置 > 隐私与安全性 > 开发者模式** 中启用 Developer Mode，并按提示重启。
6. 点击 Xcode Run，第一次出现钥匙串提示时选择允许。

本项目目前的 bundle ID 是 `sg.edu.nus.nusPresentationCapture`，并包含 Sign in with Apple entitlement。若你没有该 NUS App ID 或对应开发团队，真机签名可能失败；届时需要使用实验室开发团队，或在个人调试配置中使用自己的唯一 bundle ID 并暂时移除未获授权的 Apple 登录 capability。不要为了消除签名错误随意修改正式配置后直接提交。

真实 iPhone 访问 Mac 上的服务器时，不能使用 `localhost`。把 App 设置中的服务器地址改成 Mac 的局域网 IP，例如：

```text
http://192.168.1.20:8080
```

Mac 和 iPhone 需要在同一 Wi-Fi，且 macOS 防火墙需允许 Docker 或 Node.js 接收入站连接。

## 10. 常见问题

### `xcrun: error: invalid active developer path`

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 找不到 iPhone Simulator

```bash
xcodebuild -downloadPlatform iOS
open -a Simulator
flutter devices
```

### Flutter 依赖或生成文件异常

```bash
cd ~/Developer/presentation-capture
flutter clean
flutter pub get
flutter run
```

`flutter clean` 只清理生成的编译产物，不会删除源代码或 Git 提交。

### App 无法登录本地服务器

确认服务器 Terminal 仍在运行，并在 Mac 浏览器访问：

```text
http://localhost:8080/health
```

模拟器使用 `http://localhost:8080`，真实 iPhone 使用 Mac 局域网 IP。
