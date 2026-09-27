# QrcodeApp

手机二维码工具，当前版本 **1.1.2**。

- 普通二维码创建与扫描；每个二维码最多 500 个字符，长文本自动分页。
- 顶部按钮：扫描、复制、粘贴、清空。复制按钮复制完整文本。
- 点击“二维码工具”切换至 Cimbar 彩色流水码，支持手机离线创建、扫描及保存文件。
- 保留 RaptorQ 黑白流水码兼容模式。
- 使用项目内生成的蓝色二维码 Logo，支持 Android 自适应启动图标。

## 构建

开发环境使用 Flutter 3.24.3 / Dart 3.5.3、JDK 17、Android SDK 34。先配置本机 Flutter 和 Android SDK，再执行：

```sh
flutter pub get
flutter build apk --release
```

输出为 `build/app/outputs/flutter-apk/app-release.apk`。当前 Release 配置沿用 Android 测试签名；正式分发时应配置自己的发布证书。证书、本机 SDK 路径和构建输出不提交到仓库。

## 验证

```sh
flutter test
bash scripts/test_raptorq.sh
```

安装 Playwright 并提供 Chrome 后，可运行真实 Cimbar WASM 收发测试：

```sh
node scripts/test_cimbar.cjs
```

测试覆盖丢帧恢复、完整性校验、小文件和界面行为；两台实体手机的光学传输速度尚未实测。

## 实现与依赖

- [Cimbar 手机收发说明](docs/cimbar.md)
- [RaptorQ 协议](docs/raptorq-protocol.md)
- [Cimbar 来源与许可证](third_party/cimbar/README.md)
- [OpenRQ 来源与许可证](third_party/openrq/README.md)
- [相机插件预览比例修复](third_party/mobile_scanner/PATCHES.md)

Cimbar JS/WASM 与 OpenRQ JAR 随源码保留，供离线收发使用；第三方许可证也一并保留。Cimbar 模式建议两端使用本 App，具体封装兼容性见上述说明。

启动图标由 `assets/branding/qr-app-logo.png` 生成；如需重新生成，安装 Pillow 后运行 `python3 scripts/generate_launcher_icons.py`。
