# Android A2 实施记录

2026-11-17，基于 2df4b38。状态：A2 已完成本地场景与真机读取验证，0.2.0+2 已安装到 OnePlus 8T。

## 实现

- 单用户密码登录，尊重 todo_session 的 Max-Age/Expires；保存会话、站点、主题和快照，不保存密码。
- Dio 同源客户端读取任务、项目及校园状态；阻止重定向，退出或切站点时清理旧数据。
- 全量任务快照整体替换；合并重叠读取，按认证代次丢弃过期结果。
- 启动/前台恢复/按钮/下拉读取，失败保留带时间的只读缓存；401 返回登录。
- UI 延续固定版 Prism，真实模式没有演示修改入口；A3 再接任务写入与前台轮询。
- 单个应用私有 JSON 文件串行写入后原子替换；Android 自动备份关闭。未增加加密、客户端数据库或常驻服务。

## 已验证

- flutter analyze --no-pub 无问题，0.2.0+2 arm64 Profile APK 构建通过。
- 使用本地回环假服务实际运行生产客户端代码，验证密码错误、0/1/null、UTC+8 日期、会话恢复、合并读取、远端删除、坏响应保留缓存、校园错误隔离、拒绝重定向、切站点/旧响应丢弃、401 清理、离线重启、远端退出失败时仍清理本地、Cookie 过期和 origin 校验。记录位于 a2-local-check.log，结尾 A2_CHECK_PASS。
- 验证发现 Dart Cookie.toString 会包含 Set-Cookie 属性，已改为请求专用 name=value 序列化。
- 生产正常登录与三个 GET 接口均返回200；本轮核对读到164条任务、1个项目，响应中的校园状态时间为2026-11-17 21:02。未做生产任务写入，也未调用 POST /api/sync 或分类。

- 真机已确认真实登录、164条任务、只读详情、读取/校园状态分开展示，以及进程重启后免密码恢复会话；phone-verification.json 和截图保存实际结果。

## 真机流畅度

用户反馈 A1 全局不流畅后，实测进入 Todo 会切60Hz，Flutter 帧回调中位间隔16.64ms。原生 Activity 现请求同分辨率可用的高刷新率，OnePlus 8T 已确认120Hz及约8.3ms回调。没有改动系统刷新率设置。

另测得玻璃合成/栅格长帧；普通 BUILD 不是主要瓶颈。临时切旧 Skia 后端未改善，已保留默认 Impeller 路径。高刷新修正后仍有约19–30ms的栅格长帧，不能声称已稳定120fps；保留玻璃和 FlClash 动效，后续继续针对渲染优化。性能采样在 todo-phone-preview-20261117 目录。

## 产物与边界

证据目录：C:/Users/AndyYan/Desktop/codex/.codex_tmp/todo-android-a2-20261117。

- a2-local-check.log：本地边界场景。
- production-read-check.json：脱敏的生产接口状态/数量，无会话或密码。
- mobile/build/app/outputs/flutter-apk/app-profile.apk：正常 App 主入口的 arm64 预览包。
- 本地验证入口与 APK 在证据目录，未安装到个人手机。

未修改 Web、认证服务、SQLite 或生产同步逻辑。A3 任务写入、多端刷新闭环，以及 A4 完整日历、分类和图片仍未实施。

已安装 APK SHA256：a45ab448469ecd00907f257d71ade839689ac0f48d7b5e14d5fb804ea35d9903。
