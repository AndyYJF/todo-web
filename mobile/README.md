# Todo Android · A0/A1

这是独立的 Flutter Android 客户端骨架。UI 与动效只采用 FlClash v0.9.3 同版 Prism UI；不复用 Web 的视觉资源。

## 当前能力

- 今天、任务、四象限、更多四入口；手机浮动 Dock、宽屏侧栏。
- 明暗主题、Prism 原生卡片/按压/转场/吸附面板。
- 内存演示任务的搜索、筛选、完成、新建、编辑、日期安排和删除。
- 页面明确标识演示数据；修改只持续本次会话。

A2 的认证、网络和缓存尚未实现，没有连接生产，也没有保存真实任务或会话。日期安排为 A1 快捷选项，完整日历与象限编辑在后续业务阶段完成。

## 固定版本

- Flutter 3.47.6（framework 5fc346839b5d0eef006ed8404392afb4dfae428d）
- Dart 3.13.5
- Prism UI 0.1.2，Git 提交 63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185
- Application ID: io.github.andyyjf.todo
- Android Gradle Plugin 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0（Flutter 模板）
- 本机 Gradle 运行时：Android Studio JetBrains Runtime 25；Java/Kotlin 目标为 17
- Android NDK 28.2.13676358（r28c），Android SDK Platform 36，minSdk 24 / targetSdk 36

## 本地开发

在 mobile 目录使用 Git Bash，SDK 路径可用 FVM 的 .fvmrc 或已安装 Flutter 3.47.6。

~~~bash
flutter pub get
flutter analyze --no-pub
flutter run -d emulator-5564
~~~

通过 Flutter 文档列出的 CFUG 镜像完成本机工具下载；仅为开发命令设置镜像/PUB_CACHE，没有修改系统 PATH。

Prism UI 的 GPL-3.0 及 NOTICE 随依赖保留。独立任务图标由客户端代码绘制，没有使用 FlClash 或 Web 的品牌素材。
