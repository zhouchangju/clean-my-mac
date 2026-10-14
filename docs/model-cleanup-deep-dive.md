# 本地模型清理机制：第二轮原生反编译

日期：2026-10-12。本轮把第一轮的 `blobReferences`、`exclusiveBytes`、`shardURLs` 字段线索推进到实际分支和集合操作。仅静态读取应用包；未读取用户模型目录，未启动 CleanMyMac，未执行原程序函数或删除文件。

## 目标和方法

- 原件：`/Applications/CleanMyMac_5.app/Contents/Frameworks/LocalModelScanning.framework/Versions/A/LocalModelScanning`
- 原件 SHA-256：`a00802be223e5db1bdbbb75425982370e70bd16c61bd28d379912a31ce9cac7b`
- `lipo -thin arm64` 副本：[LocalModelScanning.arm64](../.local/evidence/round2-models/LocalModelScanning.arm64)
- 副本 SHA-256：`8e8b234c7b9b8ffc3402b1c8b7d4e148766c4e3463c00e8974fb37b65a03603a`
- REA 6.4.0 + Ghidra 12.1.4；一个 stdio MCP native session 完成 tools/list、open、函数搜索、反编译、close。`53.json` 为关闭回执。
- 地址均为上述 arm64 映像 VA。REA 完整响应、完整伪代码、原始参数、Evidence ID 见 [evidence-index.json](../.local/evidence/round2-models/evidence-index.json)。关键分支同时保留 [ARM64 汇编](../.local/evidence/round2-models/key-control-flow.asm.txt)。

**证据限制**：Ghidra 输出不是原始 Swift 源码；部分函数有 type propagation / unreachable block / indirect jump 警告。Swift 多寄存器返回和泛型 metadata 产生失真的伪 C 类型；未命名 `thunk_FUN_...` 不擅自当成确定 API。下文优先引用恢复的真实签名、明确分支、地址与调用参数，并标注仍依赖结构推断的部分。

## 1. 删除计划确实是独立计算，而非直接删扫描到的目录

Ghidra 恢复 `0xca08` 的真实 Swift 签名：

```text
LocalModelRemoval.rows(
  from: [LocalModel],
  allManifestBlobReferences: [URL: Int]?,
  isProtectedFolder: (String) -> Bool
) -> [LocalModelRemovalPlan]
```

函数先按 store 分开模型，Ollama 分支调用 `0xccc8`，LM Studio 分支调用 `0x143e0`，最后合并计划。`LocalModelRemovalPlan.init @ 0xe304` 明确接收 `model / urls / exclusiveBytes / anchorURL`。

这已确认“展示模型”和“最终准备移除哪些 URL、预计独占字节”是不同对象。**尚未跟到 UI 勾选事件及实际 FileRemover**：这里传入的 `from` 在每个调用点代表全部库存还是当前选择，不能仅由签名推断。

证据：`6.json / ev_f53b3918213013326eef7047152a71e8dfb53567156372a3bd9132208cc6ce9f`；`10.json / ev_c1a275440fff55b4b3171386330ae95ed899709b2045ec1da52354d701ffbd8e`。

## 2. Ollama：先建立全 manifest 引用账，再决定 blob 能否纳入计划

### 2.1 扫描与失败处理

`0x195c4` 拼接 home 下 `.ollama/models/manifests`，检查存在性，并调用 `0x1a284` 枚举。`.ollama` 和 `models/blobs` 是 Swift small-string immediate，`models/manifests` 有可直接查看的文字引用。

`0x1a284`：目录列表排序；跳过点开头条目；判断子项是否目录并递归，调用传入深度从 **7** 逐层减少。还比较处理后路径与 root/root+`/` 前缀；这确认有根路径边界检查，但 URL 变换对应的未命名 thunk 尚未完全命名，不能声称已证明所有 symlink 竞态被防护。

每个 manifest 进入 `0x1a984`；调用 readPrefix 时设置 **0x100000（1 MiB）** 限额，然后解析成结构。回到 `0x195c4` 时，如果 manifest 结果无效，分配 store error、设 enum tag 并抛出，释放当前模型和引用数据，不是跳过坏 manifest 后继续输出一个看似完整的引用表。目录不可读也有错误分支。尚未验证具体错误被上层 UI 如何展现。

有效 manifest 的 config digest 与 layers digest 进入 `0x21978`，其逻辑：

- 要求 `sha256:` 前缀；
- 对剩余字符做检查；
- 构造 `sha256-...` 文件名，在 `models/blobs` 下形成 URL；
- 返回的 URL 再经 Set 去重，然后对每个 URL 增加一次引用计数。

因此同一 manifest 中重复出现同一个 blob，不会在这一步简单重复增加引用次数。该字符检查的所有边界（例如 digest 长度是否严格 64）尚未逐项证实，不宣称完成了密码学 digest 验证。

证据：`8.json / ev_29fe0f59c2f17b37102011cbbeb2dfd87020f64897ed42c4d8d39279010aed2d`；`20.json / ev_9876d83db24f87b44c33528aad96042d7631e2838c26434692b86534d2fae5da`；`15.json / ev_562671073cd6750e6401e0b4642a94c07d932bbe8c0d2072866c07daf011e706`；`16.json / ev_20ce126985e646439536a0326fd0c0729c2fd2a5123cbb47357fac21f2c631f8`。

### 2.2 全局引用信息不可靠时不给 Ollama 清理计划

`0xccc8` 开头明确要求：

```text
全局引用表不为 nil
并且（全局引用表不为空，或者本次模型数组为空）
```

不满足则返回空计划。这个判断直接回答第一轮缺口：**缺失全局引用信息时，Ollama 分支采取保守停止**。它不是仅凭模型文件名就给出删除路径。

### 2.3 相同 blob 集合的 aliases 会归组

`0x12fb4` 从每个模型的 `OllamaDetails.blobURLs` 构造 Set，作为 grouping key。没有 details 或空 blobURLs 时，使用包含模型 id 的另一个 key 分支（与元数据 `unresolved` 对应）。

`0xccc8` 再：

1. 统计每个 blob 出现于多少个 **不同已解析分组**；不是把每个 alias 当成独立 payload。
2. 每组取代表模型，并保留组成员。
3. 收集并去重组成员的 manifest URLs。
4. 对当前组的 blob 集合筛选，最后把允许的 blobs 与 manifest URLs 拼为 plan URLs。

代表模型的具体排序策略涉及字符串比较/排序 helper，本轮未给产品级排序承诺。

证据：`12.json / ev_922a14a39143834bc111462db5b0d1115c5c75249c5df5a4a0fe7a19b6393c8d`；`7.json / ev_c4f535492e278a816d92eb0358bd08f4d9888e17facd8b7ddd06931f602023d2`。

### 2.4 共享 blob 保留的真实比较条件

筛选链：`0xccc8 → 0x13b4c → 0x138b0`。最后一个函数的控制流可读清楚：

- 如果当前 blob 在“跨分组引用计数”中 **>1**，跳过该 blob；
- 否则读取全局 manifest 引用计数（缺 key 在此局部函数按 0）；
- 只有 **全局引用次数 ≤ 当前组去重 manifest 数量**，才设置保留位，把该 blob 放入允许集合。

这里的“保留位”指保留在待删除 URL 集合中；不满足条件的 blob 被留在磁盘。

分析者等价表达（不是还原源代码）：

```text
candidateBlobs = group.blobSet.filter(blob =>
  resolvedGroupReferenceCount[blob] <= 1 &&
  allManifestReferenceCount[blob] <= uniqueGroupManifestURLs.count
)
plan.urls = uniqueGroupManifestURLs + candidateBlobs
```

例子：A、B 使用相同完整 blob 集合时可归为一组；若另一个组 C 也用到其中一个 blob，则该 blob 不加入 A/B 的计划。即使一组之外的模型没有进入当前候选数组，只要全局 manifest 仍引用它，第二个计数条件也会阻止移除。

这是对共享文件的实质保护，但**没有证明同时选择多个独立组时会重新联合优化回收量**。按当前函数分组条件，它可能保守保留所有跨组共享 blobs；不能向用户承诺“全选两个模型就一定释放它们共享的全部空间”。

证据：`26.json / ev_61a199f4c16d6cdc0d6b838753c6b69df3206064f3095b3cd831aaed16085ed8`（`0x138b0`）；`18.json` 是上层集合筛选包装函数。

### 2.5 exclusiveBytes 不等于所有 plan URL 大小相加

`0xccc8` 把代表模型的 `url` 作为主判断对象。如果此 URL 在多组共享，或全局引用数超过组 manifest 数，`exclusiveBytes` 设为 0；否则调用 `0x141a8`。

`0x141a8` 对组成员构造 `(model.url, saturating(sizeBytes + companionBytes))`，再用字典聚合及 `0xee2c` 求和；求和检测溢出。字段对应关系由 `get_sizeBytes @ 0xa12c`、`get_companionBytes @ 0xa1c4` 等真实 getter 佐证。

**已确认**：有独立独占计量、共享时归零分支、同 URL 聚合和溢出处理。**仍需验证**：重复 URL 时字典选择哪一条数值，以及此数值是否包括所有次要 blobs/manifest 自身尺寸。因此不能称它是精确文件系统空间模拟，也不能把 UI 模型 size 直接加总作为释放量。

## 3. LM Studio：GGUF 文件名分片只是第一道检查

### 3.1 扫描根与格式分类

`0x3090` 构造 `~/.lmstudio/models`，通过 `0x3540` 两层枚举目录，再逐个仓库目录调用 `0x3a68`。本轮只确认这个默认布局；自定义模型路径、外置盘配置读取未确认。

`0x3a68` 先获得目录内文件/尺寸映射，再找 `gguf` 候选并调用 `0x4188`。如果没有返回有效 GGUF 模型，则检查 `config.json` 并进入 `0x52f8`；后者继续检查 `safetensors`。这说明这里不只按 `.gguf` 扩展名列文件，还有另一种 config+weights 格式路线。尚未还原 config schema 的每个允许字段。

证据：`21.json / ev_32e52268c10037ce2bc40ddbbf97057b762c59c6e3471dd0cf52016c7a764e33`；`35.json / ev_5a5ca37fcab3bcfe5cd286d51c1782dafff4aa6d82dffc17a535dabc4dcd951e`；`31.json`。

### 3.2 分片文件名解析

`0x8ecc` 去除扩展名相关处理后，用 `-` 拆分；要求末段结构包含 `of`，并通过 `0x8b6c` 把编号/总数解析为整数，再将剩余 basename 拼回。可对应 `base-00001-of-00003.gguf` 这一类形式。未确认必须补足固定 5 位，不能把“例子”当成正则原文。

`0x4188` 用这些解析结果构建候选并分组，再调用 `0x5ac0` 验证每组。

### 3.3 必须覆盖完整 1..N，而且每片读取实际头部

`0x5ac0`：

1. 组非空且声明总片数为正。
2. 从成员提取 partNumber，构造 Set。
3. 构造 `1...partCount` 的 Set，调用 `0x6304` 做集合等价检查；不相等则组无效。
4. 排序后逐片调用注入的 readPrefix，校验实际数据。
5. 校验前缀长度与固定 magic，再取版本字段，要求 **版本 ≥2**。

magic 通过 `0x1804` 从静态字节数组读取，thin file `0x30b38` 确为 `47 47 55 46`（`GGUF`）；`0x1760` 把 magic 长度 4 加 4，得 8-byte 前缀长度。`0x2614` 同样检查这 8 个字节并执行 `return 1 < version`。没有发现把“扩展名是 gguf”当成唯一格式证据。

这是**头部识别**，不是完整模型可加载验证：没有读全权重，不等于校验了 tensor tables、文件尾部完整性或哈希。partNumber 用集合验证也不足以证明重复编号文件被安全消歧，重复片号仍是待测边界。

证据：`14.json / ev_66c1ff92391ba7c46a78841f8db4d504af8f6111c7e29b7abb23fe0806d4535b`；`34.json`（整数集合等价）；`37.json`（文件名解析）；`52.json / ev_9d10a3ed3eef4027d1463109c841f528f3ce2f5b40e636b319868f2c05d5931e`；[magic 字节证据](../.local/evidence/round2-models/gguf-magic-byte-evidence.json)。

### 3.4 无效分片被分离，不直接冒充正常模型

`0x4188` 在 `0x5ac0` 失败时把组内文件名放入另一集合；后续候选处理时检查这组排除名。有效分组才组合 shard filenames、尺寸与模型实体。

因此不完整/头部错误 GGUF 不能在这条路径直接冒充正常模型。**不代表它会自动成为“垃圾文件”并可删除**：是否另外展示损坏下载、是否给用户恢复提示，本轮无 UI/runtime 证据。

### 3.5 LM Studio 计划会区分文件与整个模型目录

`0x143e0` 先按目录相关 URL 建计数，然后分支构造 `LocalModelRemovalPlan`：某些仅有一个候选的目录分支调用 `isProtectedFolder`，未保护时把目录/相关 URL 纳入计划，并把 `sizeBytes + companionBytes` 计入；其他分支只组合主 URL 与 shardURLs，独占计量主要取 model.sizeBytes。

真实保护 callback 和不同粒度的计划已经确认。由于 URL 变换 thunk 未完全命名，**尚不能把某个分支严格标成“仅模型目录且无任何其他文件，所以整目录删除安全”**。应用当前是否在加载模型、目录中混入用户文件、下载中、symlink/自定义路径均需后续验证。

## 4. 自研下一版可以直接采用的设计（本项目建议）

1. **独立 Inventory 与 RemovalPlan**。模型列表显示模型大小；计划单独显示将移除的文件、保留的共享文件及预计独占空间。
2. **Ollama 建全库引用图**：先读取全部相关 manifests，每个 manifest 内去重；任意 manifest 不可读/无法解析，禁用该 store 的 blob 删除计划并解释原因。
3. **选择集合决定安全范围**：对当前选择集合求 manifest 闭包；只有引用者全部被选中才考虑 blob。删除前重新读取 manifest 集合/hash，发现变化则计划失效。
4. **模型 aliases 与 payload 分开**：相同 blob 集合的多个名称显示为一组共享模型内容，同时让用户看到会移除几个 tags/manifests。
5. **GGUF 分片作为整体**：明确缺少第几片、编号冲突、header 异常；不将无效组自动勾选为垃圾。
6. **运行中/下载中/自定义路径要额外门禁**：不能凭 8-byte header 或全局引用表推断模型不再使用。
7. **尺寸保留不确定性**：独占逻辑字节、物理 allocated bytes、最终释放量分开；共享块/APFS snapshots 交给文件系统复测。
8. **保留 manifest 与计划回执**：删除应有重检、逐项结果、可恢复策略；它们是自研要求，本轮没有证明原产品都具备。

建议后续用合成目录 fixture 验收，以下不是对原 App 的实测结果：

| 场景 | 自研期望 |
|---|---|
| A/B 完全共享 blob 集合，只选 A | 保留 B 仍引用的 blobs；明确只移除 A 的 manifest |
| A/B 部分共享，同时选中 | 重新计算联合引用，而非简单加两行 size |
| 有一个无法解码 manifest | 禁止相关 store blob 删除，允许查看已识别库存 |
| 同一 manifest 重复引用同 blob | 计数一次，不增加额外空间 |
| GGUF 1/3、3/3，缺 2/3 | 标不完整；不得按完整模型自动处理 |
| GGUF 扩展名正确但 magic 错误 | 排除正常模型识别，给出原因 |
| 重复片号/总数冲突 | 拒绝自动模型组计划 |
| 计划生成后新增 manifest | 删除前重检失败并要求重新扫描 |
| 模型目录含自建说明/微调数据 | 不整体删除目录 |

## 5. 本轮明确未完成

- 未调用/执行 CleanMyMac 清理函数，没有动态“确实保住了共享 blob”的测试。
- 未完成模型 UI 选择→rows 输入→清理 executor 的整条调用链。
- 未证明自定义 Ollama `OLLAMA_MODELS` / LM Studio storage 配置支持。
- 未证明所有模型格式、所有 digest 规则、并行下载与运行中使用检测。
- 未证明准确 APFS 可回收空间、符号链接竞态与删除重检策略。

可以据此实现一版更保守、可解释的模型库存和计划预览；实际删除能力仍应通过合成 fixture、模拟失败与独立验收后再开放。
