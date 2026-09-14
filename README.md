# Todo 待办清单

自托管的个人待办清单网站。暖纸底色 + 克莱因蓝点缀的杂志风设计，Framer Motion 全链路动画，支持校园事务自动同步。

线上地址：https://todo.fei.cx （需登录）

## 功能

- **今日视图**：当天任务 + 快速添加（`/` 聚焦输入框，回车即建），支持截止时间预设
- **全部任务**：进行中 / 已完成 / 全部 切换，按项目筛选
- **日历**：月视图，按截止日期归组，点日期看当天任务
- **甘特图**：按开始/截止时间画横道，今天竖线按真实时间定位
- **项目跟踪**：按项目分组的进度条
- **置顶磁贴**：重要任务钉成卡片墙
- **任务详情**：悬浮卡片，自定义日期时间选择器（小日历弹层），备注内图片直接渲染、点击放大
- **校园事务同步**：每 10 分钟增量拉取上游事务 API（`updated_since` 游标），完成状态双向回写，群消息原文入备注
- **登录保护**：密码登录 + HMAC 签名 Cookie（30 天会话），全站中间件鉴权
- **移动端适配**：汉堡抽屉导航、详情全屏化

## 技术栈

Next.js 16 (App Router, standalone) · React 19 · Tailwind CSS 4 · Framer Motion · node:sqlite（零原生依赖）· TypeScript

## 本地开发

```bash
npm install
TODO_PASSWORD=你的密码 npm run dev   # 不设置时开发模式默认密码 todo-dev-default
# 打开 http://localhost:3000
```

## 环境变量

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `TODO_PASSWORD` | 站点登录密码 | `todo-dev-default`（仅开发） |
| `TODO_DB_PATH` | SQLite 数据库文件路径 | `./data/todo.db` |
| `CAMPUS_API_URL` | 校园事务 API（带 token） | 不设置则关闭同步 |
| `PORT` / `HOSTNAME` | 监听地址 | 3000 / 0.0.0.0 |

## 部署

```bash
npm run build          # 产出 .next/standalone 自包含构建
node .next/standalone/server.js
```

生产用 systemd 常驻 + Caddy 反代（自动 HTTPS）。数据库是单文件 SQLite，备份 `data/todo.db` 即可；设置页也提供一键导出 JSON。
