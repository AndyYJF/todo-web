# Todo Android · A4

独立 Flutter Android 客户端，UI 与动效只采用 FlClash v0.9.3 同版 Prism UI，不复用 Web 视觉。

## 当前能力

- 单密码登录，保存 origin 绑定的会话及过期时间；不保存密码。
- 真实任务、项目和校园同步状态读取；启动、前台恢复、按钮/下拉及前台30秒轮询，后台停止。
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
- 手机请求同分辨率的高刷新率模式，最终刷新率由系统策略决定。

任务修改需要有效的服务端快照；缓存状态可保留草稿，联网刷新后再提交。未知 PATCH/DELETE 根据最新服务端状态核对，未知新建显示候选任务并由本人确认；没有客户端写入队列或自动重试。分类与校园同步同样不自动重发；已完成 A4，后台同步与手机消息提醒已纳入 A6。

## 固定版本

- App 0.4.0+4，Application ID io.github.andyyjf.todo
- Flutter 3.47.6 / Dart 3.13.5
- Prism UI 0.1.2 / 63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185
- Dio 5.11.1 / path_provider 2.1.6
- markdown 7.3.1 / url_launcher 6.3.3
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

会话、设置、草稿、单笔待确认提交和 JSON 任务快照存放在应用私有 support 目录，禁用 Android 自动备份，不引入额外数据库或加密。服务地址仅接受 HTTPS origin；HTTP 回环仅供本地验证入口显式启用。请求禁止自动重定向，不向其他 origin 发送 Cookie。

Prism UI 的 GPL-3.0 和 NOTICE 随固定依赖保留。SDK 和构建缓存不进入源码。
