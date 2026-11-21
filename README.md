# Todo 待办清单

自托管的单用户待办清单。Web 和 Android 通过同一套 Todo API 读写服务器上的任务与项目。Web 采用暖纸色、克莱因蓝和 Motion 动效。Android 使用 FlClash 同版 Prism UI 的导航、卡片和面板动效。

[打开在线版（需登录）](https://todo.fei.cx) · [Android 使用与构建](mobile/README.md) · [开发计划](docs/android-app-plan.md) · [真机验收](docs/android-a5-a6-progress.md)

## 功能

| 场景 | Web | Android 0.7.0 |
| --- | --- | --- |
| 任务管理 | 今日、全部任务、快速添加（`/` 聚焦输入框）、项目筛选、置顶磁贴 | 今日、搜索和状态筛选、新建和编辑、项目分组、置顶、草稿恢复 |
| 日程 | 月历、甘特图、项目进度 | 月历、日期范围、开始与截止时间选择 |
| 规划明天 | 导入 .ics、排程、完成状态、历史与归档补记、提醒设置 | 同步课表与规划、完成状态、历史与归档补记、系统晚间提醒 |
| 四象限 | 手动分类、AI 批量分类 | 手动选择或清除象限、AI 批量分类 |
| 校园事务 | 服务端定期同步、完成状态回写、查看同步结果 | 查看或手动触发校园同步、查看原始备注及图片、新校园任务提醒 |
| 跨端同步 | 读写服务端任务 | 前台定期刷新、离线查看快照、可选后台读取与截止提醒 |

服务端每 10 分钟增量拉取校园事务。手机的后台同步约每 30 分钟读取 Todo 服务，实际运行时间由 Android 调度。新校园任务和截止提醒可在 Android 设置中分别启用。

## Web 本地开发

使用 Node.js 24 和 npm。Web 使用 Next.js App Router、React、Tailwind CSS、Motion、TypeScript 和 Node.js 内置 SQLite。

~~~bash
npm ci
npm run dev
~~~

打开 [本地 Todo](http://localhost:3000)。开发密码默认是 `todo-dev-default`，也可以在启动前设置 `TODO_PASSWORD`。

| 环境变量 | 用途 |
| --- | --- |
| `TODO_PASSWORD` | 登录密码和会话签名密钥。上线前应设置独立密码 |
| `TODO_DB_PATH` | SQLite 文件路径，默认为当前工作目录下的 `data/todo.db` |
| `CAMPUS_API_URL` | 带 token 的校园事务 API 地址。留空时关闭校园同步 |
| `MODEL_ENDPOINT`、`MODEL_API_KEY` | AI 分类接口地址和密钥。未配置模型时使用规则分类 |
| `MODEL_NAME` | 可选的分类模型名称 |
| `PORT`、`HOSTNAME` | standalone 服务的监听端口和地址 |

## Web 部署

构建 standalone 产物并复制静态资源。启动前在运行环境中设置登录密码与数据库路径。

~~~bash
npm run build
mkdir -p .next/standalone/.next
cp -R public .next/standalone/
cp -R .next/static .next/standalone/.next/
node .next/standalone/server.js
~~~

生产环境通过 systemd 运行 Next.js，由 Caddy 提供 HTTPS。设置页可导出任务 JSON。

首次升级到规划功能时，用 `NEXT_PUBLIC_TODO_PLANNER_WEB=0 npm run build` 构建仅启用规划 API 的版本。确认旧版任务读取和新版规划接口后，再用默认配置重新构建并切换到带 Web 规划入口的版本。两次使用同一生产数据库与现有服务配置。

## Android 安装与开发

Android 0.7.0 的个人 Release 包适用于 arm64 手机，最低 Android 7.0。规划功能需要站点先升级。已有安装可用相同签名的 APK 覆盖升级，保留应用数据。连接时填写 Todo 站点的 HTTPS 地址，使用同一个站点密码登录。

Flutter 版本、构建命令、签名配置和提醒开关见 [Android README](mobile/README.md)。0.6.0 已验证真机覆盖升级及后台读取。掉帧专项仍待验收。
