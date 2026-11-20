# Todo Android 0.6.0

独立 Flutter Android 客户端，UI 与动效只采用 FlClash v0.9.3 同版 Prism UI，不复用 Web 视觉。

## 安装与连接

个人 Release APK 面向 arm64 手机，最低 Android 7.0（API 24）。使用同一签名的 APK 覆盖安装可保留应用数据。登录时填写 Todo 站点的 HTTPS 地址和站点密码。

在 **更多 → 设置 → 后台同步与提醒** 可以开启后台同步、新校园任务提醒和截止时提醒。启用提醒时按需授予系统通知权限。后台约每 30 分钟读取一次，执行时间受 Android 调度影响。

[返回项目首页](../README.md) · [真机验收记录](../docs/android-a5-a6-progress.md)

## 当前能力

- 单密码登录，保存 origin 绑定的会话及过期时间；不保存密码。
- 真实任务、项目和校园同步状态读取；启动、前台恢复、按钮/下拉及前台30秒轮询；后台可启用约30分钟的系统读取任务。
- 新建、仅修改实际改动字段、完成、置顶和确认删除；服务端确认后更新任务。
- 单个独立草稿支持关闭/重启/401后恢复；刷新不改写编辑内容。
- 一次只处理一笔业务提交；结果未知时持久化确认记录，不自动重发新建。
- 最近全量快照的只读缓存，读取失败保留快照和时间；401/退出清理会话与缓存。
- 今天、任务、四象限、更多；浮动 Dock/宽屏侧栏、主题和详情。
- 月历与日期范围任务、未设日期分组；项目搜索、计数和状态筛选。
- 手动象限与清除分类；AI 默认仅未分类，覆盖全部需独立确认，显示规则兜底结果。
- 原生 Markdown 备注与外部链接；校园图片经本站鉴权代理读取、重试与缩放查看。
- 设置集中显示主题、服务地址、会话到期、快照与校园状态，提供显式校园同步。
- App 最近读取时间与校园上游同步时间分开显示。
- 后台仅 GET Todo API，不触发上游同步；新校园任务去重提醒，已知截止时间使用系统闹钟，完成/删除取消提醒。
- 设置显示通知/准时提醒权限、后台最近尝试/成功时间与执行结果；后台401暂停调度，回到 App 重新登录，保留草稿。
- 手机请求同分辨率的高刷新率模式，最终刷新率由系统策略决定。

任务修改需要有效的服务端快照；缓存状态可保留草稿，联网刷新后再提交。未知 PATCH/DELETE 根据最新服务端状态核对，未知新建显示候选任务并由本人确认；没有客户端写入队列或自动重试。分类与校园同步同样不自动重发；A6 已接入系统后台读取和消息提醒，默认关闭，由设置页启用。

## 固定版本

- App 0.6.0+6，Application ID io.github.andyyjf.todo
- Flutter 3.47.6 / Dart 3.13.5
- Prism UI 0.1.2 / 63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185
- Dio 5.11.1 / path_provider 2.1.6
- markdown 7.3.1 / url_launcher 6.3.3
- AndroidX WorkManager work-runtime 2.12.0（原生后台调度）
- AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0
- Gradle JVM 为 Android Studio JBR 25；Java/Kotlin 编译目标 17
- Android compile/target 36、min 24；NDK 28.2.13676358

## 开发

在 mobile 目录使用 Git Bash 和 Flutter 3.47.6：

~~~bash
flutter pub get
flutter analyze --no-pub
flutter run -d <device>
flutter build apk --release --target-platform android-arm64 --no-pub --target lib/main.dart
~~~

会话、设置、草稿、单笔待确认提交和 JSON 任务快照存放在应用私有 support 目录，禁用 Android 自动备份，不引入额外数据库或加密。服务地址仅接受 HTTPS origin；HTTP 回环仅供本地验证入口显式启用。请求禁止自动重定向，不向其他 origin 发送 Cookie。

Prism UI 的 GPL-3.0 和 NOTICE 随固定依赖保留。SDK 和构建缓存不进入源码。

后台调度受 Android 省电、网络和强行停止限制；精确到期提醒需对应系统授权。首次启用以当前任务为基线，不批量提醒已有或过期任务。后台快照独立保存，并绑定会话与写入版本，不覆盖草稿或已确认修改。

个人 Release 使用现用证书覆盖升级，详见 [签名说明](SIGNING.md)。性能专项按用户要求继续暂缓，A5 本轮验证覆盖系统返回、键盘、大字体与减少动画。
