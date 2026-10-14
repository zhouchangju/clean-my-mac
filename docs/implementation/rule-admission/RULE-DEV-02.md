# RULE-DEV-02：npm _cacache/tmp 过期普通叶子

状态：previewOnly；版本仅实测 npm 11.19.1 / Node v26.10.0 / cacache 20.0.4。默认POSIX cache为 `~/.npm`（本机安装的 @npmcli/config 定义）；flatten 将实际cache加 `_cacache`。生产 root 为 home-relative `.npm/_cacache/tmp` 与所选范围交集。自定义 cache 只能显式选择根；不得读取凭据来猜根，不改 HOME。

用途/格式依据：安装源码 `cacache/lib/util/tmp.js` 用 `path.join(cache,'tmp')`，UUID普通临时文件名或 mkdtemp 目录；content/write.js 用 `wx` 写暂存，成功后 move 到内容寻址目录，失败 finally 删除暂存。由此能证明 tmp 是写入过程工作区，**不能证明它在没有 npm 前台窗口时不被使用**。源码hash与快照留档；`@npmcli/config` definitions.js 419–435为根映射依据。npm官方背景：https://docs.npmjs.com/cli/cache/；本调查主要使用当前已安装源码，未依赖旧网页版本。

受控实际验证：0700 fixture profile，调用该已安装 cacache 的 tmp.mkdir 生成目录、自建普通叶子并设 mtime 为8天；put/get确实可用。将叶子移至fixture staging，再调用同API得到另一tmp叶子且内容hash一致，get成功，原叶子无覆盖恢复hash一致。没有 npm install、没有安装依赖/联网；**暂存叶子内容由调查脚本提供，非中断 npm install 的真实残留**，完整 npm CLI 再生成/正常使用链仍 UNVERIFIED。7天是产品默认设计，不是 npm 官方有效性承诺；若ctime/mtime未知或年龄不足必须拒绝。

保护反例：只 tmp 后代普通叶子；content-v2、index-v5、_npx、_logs、.npmrc、源码/配置/凭据不纳入。自建 fixture 有缓存内容/配置/会话/凭据 sentinel，以及 tmp symlink、硬链接与fresh普通叶子。独立oracle确实识别其类型/链接数/不足7天，但产品RuleEngine拒绝证据尚需产品测试；不声称 AC-07/14 PASS。

活动覆盖：活动 npm/node即busy。现场 ps 成功观察51个node，保守busy；无法可靠识别所有同缓存worker，也没有第三方锁协议阻止新任务。无已知进程/枚举失败/版本未知仍unknown；不能按进程名称外观排除“无关node”后推成inactive。

允许动作：仅分析/预览；不得 Trash/Purge。失败恢复本次只无覆盖恢复自建 staged leaf；产品journal、crash、Trash收据、同卷/身份竞态不在本调查验收范围。永久删除不能恢复。

AC-09 / M2 BLOCKED：真实tmp用途已核验，有限API再生成已运行，但完整中断残留再生成与完备activity仍缺口。
