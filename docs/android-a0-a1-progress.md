# Android A0/A1 实施记录

2026-11-17；范围：计划对抗审查、独立 Android 工程、FlClash 风格的 UI 与动效演示。

## 结果

四入口（今天、任务、四象限、更多）、浮动 Dock/宽屏侧栏、大标题、连续圆角卡片、任务详情路由、表单面板、明暗主题均已实现。界面与动效只使用 FlClash v0.9.3 同版 Prism UI；没有导入 Web 的样式、字体、图片、图标或布局。

新建、编辑、完成、置顶、删除、搜索和分组均操作内存演示 Store；页面标有演示状态。尚未添加网络、认证与缓存依赖，也没有访问或修改生产。

## 对抗审查与修正

详见 [计划审查](android-plan-adversarial-review.md)。修正 Web 视觉边界、旧刷新响应覆盖新写入、会话/缓存与 origin 绑定、A1/A2 依赖边界及具体 UI 验收路径。

运行验证另发现并修正：Prism 紧凑面板与页面的标题边距机制不同，表单统一使用 appBarInset 与原生紧凑标题栏尺寸；系统关闭动画时增加同风格静态导航/路由/面板，清理重复读屏标签和面板内系统安全区。正常动效仍直接采用固定版 Prism 实现。

## 固定环境

| 项目 | 版本 |
| --- | --- |
| Flutter / Dart | 3.47.6 / 3.13.5 |
| Prism UI | 0.1.2 / 63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185 |
| AGP / Gradle / Kotlin | 9.1.0 / 9.3.1 / 2.4.0 |
| Gradle JVM | Android Studio JetBrains Runtime 25；Java/Kotlin 编译目标 17 |
| Android | compile/target 36，min 24；NDK 28.2.13676358 |
| 验证设备 | Pixel_7_API_35，Android 15，x86_64 模拟器 |
| App | io.github.andyyjf.todo，0.1.0+1 |

NDK 旧版命令行安装器与当前包元数据不兼容，改用官方 r28c Windows 归档，已核对官方大小和 SHA1。SDK 与下载缓存位于工程之外，不进入源码。

## 验证

- flutter analyze --no-pub：通过，无问题。
- flutter build apk --debug --target-platform android-x64 --no-pub：通过。
- 模拟器实际完成演示任务的新建、编辑、完成与确认删除，计数和列表跟随同一 Store 更新。
- 实际检查四页、详情、表单、主题、横屏侧栏，修正了面板标题重叠。
- 系统三项动画设置为 0：静态导航、表单新建与深色主题操作通过；随后恢复原值。
- App 内部短拖取消保留详情，长拖返回保留任务列表；基于新的 UI 层级文件确认。
- 系统返回与面板取消、键盘弹出时标题栏保存区域均已检查。

## 证据与产物

证据目录：C:/Users/AndyYan/Desktop/codex/.codex_tmp/todo-android-a0-a1-20261117。

- 浅色：today-light.png、tasks-light.png、quadrants-light.png、more-light.png。
- 深色：today-dark.png、more-dark.png。
- 详情与最终面板：detail-light.png、editor-light.png；键盘：editor-keyboard.png；拖动取消：back-gesture-cancel.png。
- 宽屏：wide-layout.png。
- 减少动画：reduced-editor.png、reduced-dark.png。
- 实际交互录屏：todo-a1.mp4（约 66 秒，1080×2400，H.264）；包含导航、详情、面板、取消/返回和主题切换。
- 调试 APK：mobile/build/app/outputs/flutter-apk/app-debug.apk；仅 x86_64 模拟器构建。

## 后续

A2 开始接入单密码登录、会话生命周期、真实任务/项目/校园状态读取和只读缓存；A3 完成多端写入闭环。当前 APK 不提供真实同步。arm64 分发包、正式签名、真机帧率与大字体等完整验收留在 A5。没有以调试模拟器记录宣称真机动效性能已验收。

最终调试 APK SHA256：14fdc8efb1f058ad552c40d511ca0662536e9ebd5bc3f32025292d6bca081490。
