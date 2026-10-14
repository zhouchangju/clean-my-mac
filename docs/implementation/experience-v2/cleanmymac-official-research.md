# CleanMyMac 官方页面与交互研究

查询：2026-10-13。对象：当前 MacPaw `/support/cleanmymac/knowledgebase/`，排除 CleanMyMac X / 3 / Classic 的旧指南。本任务采用 reverse-engineer-anything 的独立问题与证据分工原则，但证据来源为官方网页，并未启动 REA 原生会话或操作原软件。本文件只做研究，不改源码。

## 证据边界

- **已观察**：web 搜索/打开官方文本、更新日期、文章内的图片链接及文字操作说明。未查看本文链接图片的像素，不能从图片标签推断布局尺寸、配色或具体显示值。
- **官方描述**：以下页面功能/结果/按钮语义均来自指南，不能冒充本机原App运行证据，也不能证明其安全性、性能或内部算法。
- **推断/建议**：显式列在“对本工具的落地”段中，是设计判断。
- **unknown**：安装版本与各发行渠道是否一致、权限拒绝/取消/失败后的真实状态、扫描实际覆盖、删除/恢复内部语义、精确空间口径。未执行扫描或清理，未访问凭据、安装或系统优化。

## 逐页记录

### 1. Smart Care：统一开始与结果看板

**官方描述**（2026-08-11）：入口 Scan；串行组合 Cleanup、Protection、Performance、Applications 与下载目录重复项检查。结果按模块 tile 展示空间、威胁数、维护任务、可更新应用、重复项；Review 进入详情，Run 执行所选任务。官方默认选中全部任务，可取消单 tile。Start Over 需确认；Scanning 设置可以排除模块/类别/组，排除模块结果以灰 tile 保留并提供 Enable。[Smart Care](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care)

**对本工具的落地（推断）**：首页承担“我现在能做什么”：主盘容量、明确扫描范围、开始只读扫描。完成后显示“空间分布 / 需审阅大文件 / 缓存规则发现 / 未覆盖目录”的 tile，点击卡片进入真实结果。保留未扫描/被排除状态，不能显示假0。沿用本工具默认空选择；缓存previewOnly不因看板数字变成可清理。

**unknown**：原App运行中聚合进度、取消语义、partial结果和错误提示；不要根据“核心模块”宣传推断全盘已完整覆盖。

### 2. Cleanup：先摘要，再类别管理器

**官方描述**（2026-10-12）：Scan 后先摘要；Review All Junk 进入 Cleanup Manager，单tile Review直接类别；支持按名称/大小搜索排序、Finder/info/ignore/Quick Look。Select可全选或Smart Selection，Clean Up作用于当前类别。执行后 View Log / Review Remaining Items / Done 三个出口。[系统垃圾流程](https://macpaw.com/support/cleanmymac/knowledgebase/system-junk)

**官方分类描述**（2026-10-12）：用户缓存按应用归组；日志、Xcode产物等是独立组。备份/文档版本有保留逻辑，Xcode模块缓存与Archives不自动选中。这是MacPaw产品描述，未证明任一组适用于我们的执行。[分类解释](https://macpaw.com/support/cleanmymac/knowledgebase/system-junk-cleanup-list)

**对本工具的落地（推断）**：把“候选”改为用户理解的“缓存与开发产物”，结果按用途与应用分组，每组显示占用、条目数、能力状态及原因；按文件列表进一步审阅。说明缓存用途、重建代价、活动未知；只展示实装规则实际匹配的组。类别大小与可执行估计分栏，保护/previewOnly仍可查看但不可勾选。

**unknown**：官方“安全删除/提速”的营销描述不作为准入依据；不能复制默认选中、整目录删除、语言/系统缓存/备份清理能力。

### 3. Space Lens：主盘入口与可下钻的空间地图

**官方描述**（2026-08-06）：默认主驱动器，可切换卷/文件夹，再点Scan；扫描后最大条目优先列表与不同大小气泡并列，Other items展开其余。悬停联动图与列表；顶部空间条区分Used/Free/Purgeable/Selected。双击目录或点气泡下钻，前后退、面包屑、空白区双击上移；系统保护项目不能选。[入口](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens)、[结果浏览](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results)

**官方描述**：Review and Remove打开所选清单，显示路径可Finder定位，可以取消项目或返回地图，再Remove。[最终审阅](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-cleanup)

**对本工具的落地（推断）**：首屏可发现的“分析主磁盘”预设与“选择文件夹”并列，按用户当前授权与实现边界明确实际scope后启动。默认选中的UI预设不等于自动枚举Home；点击才建立本次范围。结果页“排行 + 空间图 + 面包屑”共享数据，不让用户先去列表找一条可删项。目录可分析下钻，执行仍固定普通叶子，禁止目录整体删除。预算有限可用条形/treemap替代气泡，关键是排行榜和层级导航。

**unknown**：官方大小/Selected字段是否 logical、allocated或独占量。我们必须保持logical/allocated/估计/unknown独立；purgeable不与候选相加，Trash不宣称释放。原App是否跳过系统/云等领域仍须runtime证据。

### 4. My Clutter：文件任务卡与多维审阅

**官方描述**（2026-10-01）：下拉选位置→Scan→分类tile→Review All Files或单tile Review→Manager。大旧文件≥50MB，按类型、大小、访问日期分组；可看所有/已选，名称/大小/日期搜索排序；不自动选择用户文件。Remove永久删除，且只作用当前类别；结果有日志/继续审阅/Done。[大旧文件](https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old)

**官方描述**：Downloads按下载来源应用分组，支持ignore；Duplicates按重复组/文件类型审阅，展开每个副本的路径/日期/大小，组动作支持智能选择；不同入口可能只展示最近三个月重复项。[下载文件](https://macpaw.com/support/cleanmymac/knowledgebase/downloads)、[重复文件](https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files)

**对本工具的落地（推断）**：现有大文件页补齐类型、阈值、日期筛选及“仅已选”，显示真实选择数和范围；下载目录作为明确scope快捷入口。未知访问时间不能标为“从未使用”。我们保持自有512MiB默认可调，不照抄50MB；用户文件只允许受控Trash。重复/相似图需内容oracle与保留策略，当前不可用假卡片或按名称称重复。

**unknown**：访问日期如何采集、浏览器来源归因算法、重复hash算法/共享文件处理、永久删除保护机制未实测。

### 5. Applications：推荐摘要与应用资源树

**官方描述**（2026-09-17）：Applications Scan→推荐审阅/更新/移除的tile→Manage My Applications→Uninstaller→选择→Uninstall→结果。按应用大小、名、上次打开日期排序；含资源总大小，展开资源；All/Unused（6个月）/Selected/Store/Vendor/Plugins等分组，系统App排除。[应用管理](https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller)

**官方描述**：当前My Tools包含 App Updater、App Leftovers；发行渠道会限制功能。[工具目录](https://macpaw.com/support/cleanmymac/knowledgebase/my-tools)、[版本差异](https://macpaw.com/support/cleanmymac/knowledgebase/missing-features)

**对本工具的落地（推断）**：借鉴“应用归属 + 占用 + 展开路径”，帮助理解缓存是谁产生的；当前App bundle/关联资源仍只读保护。卸载、更新、残留清理需独立需求与共享归属证明，不能因应用大就挂可执行Uninstall。

**unknown**：资源关联完备性、跨应用共享归属、last-open来源；官方差异表内部有macOS Updates不同表不一致，不能据此承诺当前平台更新能力。

### 6. Performance：按任务解释，而非一张总优化按钮

**官方描述**（2026-08-06）：Scan后建议tile、weekly维护组合；Review与Run Tasks并列，View All Tasks列全部任务。任务包括DNS、purgeable、Spotlight、Mail、RAM、Time Machine快照等；部分发行渠道无维护能力。[维护任务](https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks)

**对本工具的落地（推断）**：“优化”应在当前存储目标内解释为腾出空间建议：查大目录、审阅开发产物、查看无法扫描区、处理恢复事务。每条建议写明依据/预计成本/下一步，点击导航到对应结果；不能以空列表证明“已优化”。无后台服务、提权、进程终止/系统维护的当前范围应保持。

**unknown**：原App维护实际命令、有效性/耗时/失败与恢复；官方说任务能改善性能不等于本机证据。不要实现清RAM、快照删除或DNSflush来凑分类。

### 7. Protection：风险详情与能力限制

**官方描述**（2026-08-06）：Protection支持Configure Scan调整深度/目标；Scan结果tile快速Remove或Review。威胁详情列名称/类型/关联文件和描述；隐私按浏览器/近期项/Wi-Fi分组；权限按权限类和App计数审阅，Revoke操作。[恶意软件](https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal)、[隐私](https://macpaw.com/support/cleanmymac/knowledgebase/privacy)、[权限](https://macpaw.com/support/cleanmymac/knowledgebase/app-permissions)

**对本工具的落地（推断）**：无需仿制杀毒页。将我们的“保护与扫描覆盖”做成实际安全信息：敏感子树未深入、链接/跨卷已跳过、权限拒绝、规则未准入、不可执行原因；提供定位和重扫入口。不可把保护跳过等同安全扫描通过，也不能读取浏览器密码或会话做“优化”。

**unknown**：本机威胁检测/隐私清除/权限修改链均未实测；本文未读取任一用户浏览器数据。

### 8. Settings：扫描范围、忽略项与原生入口

**官方描述**：菜单或⌘,打开Settings，默认General；Smart Care的Scanning设置按模块/类别/组控制，取消父节点取消下级，结果仍显示关闭tile。Ignore List用于保持不希望再出现的项；Protection另有后台扫描及额外目标设置。[设置入口](https://macpaw.com/support/cleanmymac/knowledgebase/open-settings)、[扫描设置](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care)、[忽略列表](https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety)

**对本工具的落地（推断）**：保留原生菜单/⌘,，集中阈值、并发、扫描范围/覆盖说明、忽略项和本地数据管理。生效配置显示在结果页；设置变化使计划失效。区分“不扫描”和“扫描但不可清理”，关闭分类仍保留明确状态；当前不增加后台扫描、联网或自动权限申请。

**unknown**：官方所有Settings tabs和运行时联动未完整实测；我们只承认上述官方文字已核对。

## 可落地的体验契约（本工具建议，非原App观察）

1. **开始**：默认显著主盘分析入口，旁边可改目录；明确列范围/权限/只读模式。点击后才扫描，不以root `/`的机械遍历宣称全盘完整。
2. **过程**：扫描状态、实际条目数/已发现占用、当前范围和停止；没有总量时无虚假百分比。已知权限缺口显示而非等待完成后默默消失。
3. **完成看板**：本次范围、扫描耗时/时间、coverage；卡片汇总空间分布、大文件、缓存与开发产物、保护/未知。每张卡可跳详情，未扫描和0条严格区别。
4. **探索**：体积排行与可下钻层级图；类型/应用/用途分类是同次扫描的不同视图，不能重复加总。名称、路径、logical/allocated、状态/理由一屏可看。
5. **审阅**：保持空选择；已选计数/估计持续可见，隐藏已选明确提示；Finder/详情/ignore提供判断上下文。只选当前合格固定叶子；不隐藏拒绝原因。
6. **计划/执行**：显式显示动作、不可恢复性、选项/范围/到期和阻塞；规则previewOnly只预览。不同类别/筛选切换不能暗中扩大执行集合，确认绑定当前hash。
7. **结果**：成功/拒绝/失败/未知真实计数、日志、继续审阅/返回看板；Trash结果称已移入，不把估计算作释放；恢复入口依据receipt而非假“撤销”。

## 研究覆盖与剩余限制

请求的8个主页面已找到当前官方指南并整理：均为“官方描述已核验 / 原App运行UNVERIFIED”。Space Lens入口、浏览、最终审阅三段分别有来源；Cleanup与My Clutter完整流程均有来源。My Tools作为任务捷径补充研究。

最新页面10月12日的AI Clutter指南将它放在Cleanup；10月1日My Tools表把父模块写成My Clutter，存在官方页面间差异。以明确操作步骤作主要信息，并保留差异，不替作者猜安装版路由。全盘扫描TCC盲区、APFS空间语义、执行安全、规则准入仍必须用我们产品的测试证明；此报告不改变AC状态或清理授权。
