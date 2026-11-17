# Todo Android · A2

独立 Flutter Android 客户端，UI 与动效只采用 FlClash v0.9.3 同版 Prism UI，不复用 Web 视觉。

## 当前能力

- 单密码登录，保存 origin 绑定的会话及过期时间；不保存密码。
- 真实任务、项目和校园同步状态读取；启动、回到前台、按钮及下拉刷新。
- 最近全量快照的只读缓存，读取失败保留快照和时间；401/退出清理会话与缓存。
- 今天、任务、四象限、更多；浮动 Dock/宽屏侧栏、主题和详情。
- App 最近读取时间与校园上游同步时间分开显示。
- 手机请求同分辨率的高刷新率模式，最终刷新率由系统策略决定。

A2 真实数据为只读预览，新建、编辑、完成、删除和同步轮询闭环从 A3 接入。没有发送任务写入、校园同步或 AI 分类请求。原 A1 演示编辑器保留在源码，真实界面没有入口。

## 固定版本

- App 0.2.0+2，Application ID io.github.andyyjf.todo
- Flutter 3.47.6 / Dart 3.13.5
- Prism UI 0.1.2 / 63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185
- Dio 5.11.1 / path_provider 2.1.6
- AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0
- Gradle JVM 为 Android Studio JBR 25；Java/Kotlin 编译目标 17
- Android compile/target 36、min 24；NDK 28.2.13676358

## 开发

在 mobile 目录使用 Git Bash 和 Flutter 3.47.6：

~~~bash
flutter pub get
flutter analyze --no-pub
flutter run -d <device>
flutter build apk --profile --target-platform android-arm64 --target lib/main.dart
~~~

会话、设置和 JSON 任务快照存放在应用私有 support 目录，禁用 Android 自动备份，不引入额外数据库或加密。服务地址仅接受 HTTPS origin；HTTP 回环仅供本地验证入口显式启用。请求禁止自动重定向，不向其他 origin 发送 Cookie。

Prism UI 的 GPL-3.0 和 NOTICE 随固定依赖保留。SDK 和构建缓存不进入源码。
