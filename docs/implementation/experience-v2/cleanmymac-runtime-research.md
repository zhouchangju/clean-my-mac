# 本机实际页面观察（2026-10-13）

目标：`/Applications/CleanMyMac_5.app`，沿用已记录5.7.1但此次未重新核验bundle版本。通过CUA精确路径选应用；只切页、观察窗口与范围控件、打开/关闭设置，没有点击Clean/Remove/Run维护、连接云账户或改权限。原生UI观察与官方文档研究分开。工具回执在本线程CUA记录，以下保留可复核观察摘要，不伪造截图文件。

| 页面 | 当前实际可见 |
|---|---|
| Smart Care首页 | Quick Scan、System Tune-up、Security Check；统一Scan入口 |
| Cleanup首页 | System Junk、AI Clutter、Mail Attachments、Trash Bins；大标题/简短说明/统一Scan |
| Space Lens首页 | Visual Storage Map、Hidden Files Uncovered、Large Folders Overview；默认Macintosh HD；卷菜单含内外盘与Choose folder |
| Space Lens结果 | 顶部卷/路径与容量，左侧当前层级大目录按占用排行，右侧面积不同的气泡，底部卷空间条、No Items selected和disabled Review and Remove；Other items和Purgeable Space单列 |
| Protection首页 | Malware Removal、Privacy Check、Application Permissions；Configure Scan；Moonlock说明 |
| Performance首页 | Maintenance Tasks、Login Items、Background Items |
| Applications首页 | App Uninstaller、App Updater、File Leftovers |
| My Clutter首页 | Large Files、Duplicates、Similar Images、Downloads；用户目录范围选择器 |
| Cloud Cleanup首页 | Secure connection说明、Connect iCloud/Google Drive/OneDrive/Dropbox；未连接 |
| Settings General/Scanning | General/Scanning/Notifications/Menu/Protection/Email Cleanup/Ignore List；本机显示已有Full Disk Access；Scanning按模块配置，可展开层次；未改勾选 |

## 观察限制与范围差异

尝试用Space Lens选择本次创建的样例目录（marker与有限真实文件，路径存在于`.local/verification/experience-v2/cmm-fixture.json`）后，UI进入了**Macintosh HD**结果，实际显示根和数据并不等于样例根。不能称为fixture扫描通过，不能推断这些结果由本次新扫产生；可能为现有扫描/缓存的显示或选择未生效，尚无证据。记录的高层根目录占用与项数不拿来作本软件expected或可释放量。本报告省略私人机器实际容量数字。

曾看到Stop AX但按钮不能点击（cannotClickOffscreenElement）；Escape无变化，调整窗口zoom后观察结果页，再切页后主按钮已是Scan。没有终止其他应用、关闭软件或执行清理。结果产生/扫描结束的内部时序仍unknown。调整窗口后已再次调用zoom恢复，设置窗口关闭。

## 对本工具的直接修正

- 入口默认主盘，而不是空目录表与禁用Start；用户点击才开始只读扫描。
- 结果展示以同层排行、图和面包屑组织，不能把整个树父目录与子文件混在一张排行榜中。
- 摘要卡与细节有清晰入口；用户无需自行在分页表中发现下一步。
- 分析/保护/选择/操作分开：受保护应用应可只读计量，但不能因它很大变成清理候选。
- 保持本软件逻辑/分配/估计口径，未知/权限缺口单列。竞品的Purgeable Space不得成为我们虚构的新字段。

没有进行新的反编译：REA当前工具会话查询显示未打开artifact，既有静态逆向只作背景。此次页面/结果研究主要由真实CUA观察与最新官方指南支持，不声称完整恢复原算法。
