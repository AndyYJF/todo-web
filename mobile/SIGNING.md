# 个人 Android 分发签名

Release 使用本机固定的 android/.signing/todo-personal.keystore，由 android/signing.properties 引用；两者均不入库。配置字段见 android/signing.properties.example。缺少本地配置时 Release 构建会停止，不静默切换其他签名。

为覆盖升级并保留现有会话、草稿和数据，本次固定沿用 A0–A4 预览包已有的证书（原开发证书），不更换成另一把新密钥，也不卸载应用。

证书 SHA-256：D6:D5:B1:24:EA:22:BB:92:E2:11:31:45:34:68:46:CB:75:46:2B:7E:EA:45:0A:7E:A3:C5:8D:12:D2:D4:53:93。

在 mobile 目录使用固定 Flutter SDK：

~~~bash
flutter build apk --release --target-platform android-arm64 --no-pub --target lib/main.dart
adb install -r build/app/outputs/flutter-apk/app-release.apk
~~~

Release 关闭调试，沿用同一证书和 Application ID io.github.andyyjf.todo。签名配置无需生产站点、校园或模型凭据。
