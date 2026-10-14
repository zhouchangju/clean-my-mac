# Local Mac Cleaner 应用图标

青绿丝带形成开放的 C，表达扫描、整理与空间释放；暖白四角星表达清理后的轻盈。深海色圆角底呼应应用的 teal 主色，保持 Dock 中的轮廓识别。

- `icon-master.png`：imagegen 内置工具生成的原始透明图稿。
- `icon-1024.png`：1024 × 1024 通用 PNG。
- `LocalMacCleaner.icns`：macOS 应用图标，包含 16–1024 像素表示。
- `LocalMacCleaner.iconset/`：macOS 标准尺寸资源。
- `generation-prompt.txt`：生成提示词。

Xcode 项目的 Debug / Release 已设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，并将 `App/LocalMacCleaner/Assets.xcassets` 加入资源阶段。由 Xcode 编译标准 macOS AppIcon 资源并生成应用图标元数据。运行 `scripts/build-app.sh` 后，新构建的应用可在 Finder 和 Dock 使用此图标。现有运行实例需要退出并重新打开才会加载新的应用包资源。
