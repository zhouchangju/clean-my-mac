# CleanMyMac 5.7.1 界面观察

日期：2026-10-12。通过 CUA 操作 `/Applications/CleanMyMac_5.app`，截图和辅助功能树保存在 `.local/evidence/ui/`。这是实际页面观察；扫描结果页、清理确认和清理完成页尚未实测。

## 已观察到的结构

左侧导航：Smart Care、Cleanup、Protection、Performance、Applications、My Clutter、Space Lens、Cloud Cleanup、My Tools、My Activity。主页面以大标题、简短功能说明、分类入口和底部圆形 Scan 为主；每个模块以不同图标/色彩识别，操作起点一致。

| 页面 | 实际可见内容 | 证据 |
|---|---|---|
| Cleanup | System Junk、AI Clutter、Mail Attachments、Trash Bins；Scan | `01-cleanup-intro.png`、`08-final-cleanup.txt` |
| Applications | App Uninstaller、App Updater、File Leftovers；Scan | `03-applications.png/txt` |
| My Clutter | Large Files、Duplicates、Similar Images、Downloads；用户目录选择器；Scan | `05-my-clutter.png/txt` |
| Space Lens | Visual Storage Map、Hidden Files Uncovered、Large Folders Overview；Macintosh HD 卷选择器 | `04-space-lens.png/txt` |
| Settings / General | Scanning 与 Ignore List 等 tab；当前界面显示已具有 Full Disk Access | CUA 对话观察，未新增权限 |
| Settings / Scanning / Smart Care | 可以分模块展开；本机当前显示选中了五个模块，Cleanup 下可见 System Junk/Mail Attachments/Trash Bins | `06-scanning-settings.png/txt` |
| Settings / Scanning / Cleanup | System Junk、Mail Attachments、Trash Bins、AI Clutter 独立配置 | `07-cleanup-settings.png/txt` |

设置的勾选状态是**本机现状**，不能当作出厂默认值。Smart Care 与 Cleanup 两处观察到的列表不同，也不能单凭 UI 列表断言运行时不会包含 AI Clutter。没有切换任何扫描勾选项。

## 交互调查边界

侧边导航、设置窗口、tab 切换、展开扫描分类均成功。多个具有相同 accessibility identifier 的展开按钮令 AX 定位失败，依据截图坐标完成展开。

主界面 Scan 的 AX 点击持续返回 `cannotClickOffscreenElement`。尝试置前、调整尺寸、全屏、菜单 Scan、键盘和可见区域坐标后，最终仍为首页，没有观察到扫描进度或结果。`02-scan-state.txt` 名称来自尝试步骤，内容仍是首页，不能作为“扫描已启动”的证据。没有点击 Clean/Remove，也没有真实删除验收。

调查期间进入过全屏，已通过 View → Exit Full Screen 退出；设置窗口已关闭，最终停留 Cleanup 首页。当前同 bundle identifier 还存在 `/Volumes/CleanMyMac/CleanMyMac_5.app`，因此全程按 `/Applications` 的精确路径选择目标；没有改动安装镜像。

## 可以复用的交互思想

1. “系统可重建内容”与“用户文件整理”在导航层分开，避免把大文件或模型一概称为垃圾。
2. 扫描前显式选择卷/目录，范围与结果数量一起呈现。
3. 扫描范围、扫描结果的默认选择、最终清理计划是三种不同状态，不应共用一个布尔开关。
4. 设置提供分模块范围和长期忽略策略；一次清理选择不应隐式更改之后的规则。
5. 自用工具的结果解释与操作历史比装饰性动效更优先；低存储场景应直接显示内置卷收益与可重建成本。

结果列表分栏、风险提示和回执的具体自研方案见 [self-cleaner-design.md](self-cleaner-design.md)。其中未实际观察的布局明确属于设计建议。
