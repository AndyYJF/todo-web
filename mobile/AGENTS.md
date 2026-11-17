# Android 客户端约束

- UI、布局、字体、色彩、图标与动效仅参考固定版本 FlClash/Prism UI；不复用 Web 资源或设计。
- Web 只提供 API 与业务数据语义。
- A0/A1 仅内存演示，明确标识，不连接生产、不引入认证或网络/持久化依赖。
- 使用 Flutter widgets 与 prism_ui，不使用 Material/Cupertino 外观替代已选定组件。
- 依赖保持固定引用；动效优先沿用 Prism 的组件和参数。
