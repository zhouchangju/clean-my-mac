# REA 原生反编译实证

日期：2026-10-12。目标为已安装 CleanMyMac 5.7.1 的 SystemJunkScanning framework，arm64。这里只解释静态控制流，不声称实际执行了扫描或恢复了原始源码。

## 工具与目标身份

- REA 6.4.0，Ghidra 12.1.4，JDK 21.0.12.1。
- 原文件：`/Applications/CleanMyMac_5.app/Contents/Frameworks/SystemJunkScanning.framework/Versions/A/SystemJunkScanning`。
- 原 universal 文件 SHA-256：`408f7c54625e60473755bde876ee15da64a261bab3b5334d81abf6926a286295`。
- 通过 `lipo -thin arm64` 写入独立分析副本 `.local/binaries/SystemJunkScanning.arm64`；原 app 未修改。
- arm64 副本 SHA-256：`e8394daa5f50555ded0b003575ce0563102cafd2bd2572f07e7112d4d88f3f63`。

首次针对 universal LegacyScanningCore 的 REA 调用返回 `architecture_unsupported`，因此该错误回执不算反编译成功。REA 当前 Ghidra adapter 要求这类目标先提取单架构切片。随后单架构目标成功返回以下四个函数。

## 已回答的问题

| 函数 / VA | 观察 | REA Evidence ID |
|---|---|---|
| `CMCacheScanTask.scan` / `0x672c` | 组合 dsStoreFileNamePredicate 与知识库 ignore 谓词；取候选；累计进度；取消则返回空结果；否则 map 为扫描结果 | `ev_dafd2ce42752298b1634a93891d39f2bb6d1cea8aeb6a2901ff1584dac05a0b2` |
| map block / `0x69fc` | pause/cancel → ignore → KB 查询 deep-search → 计量或子项细分 → 自动选择状态 → 文件模型 | `ev_57e7cc261852ed648aacd010ac8d505672b98e5cd4ace0bb9f6d231ef1a993f3` |
| `_performDeepSearchForURL:withFilterPredicate:` / `0x6c2c` | 枚举一级 children，逐项取消/过滤/计量，构建层次结果；空组返回 null | `ev_d2a003336d5f384926b44d735a6a6af9f54dfd283237e06d0b742aeeb67afa9c` |
| `_fileSizeAtURL:cancellationFlag:` / `0x6f34` | 普通 fileSizer 为 0 且文件不可读，才检查 privileged performer 授权；已授权时使用 helper 获取大小 | `ev_3dbae47dca3dc7ec78b0ebed70e112ea01362138e37bfda79c343b9bb4dc3d52` |

对应文件：`.local/evidence/cache-scan-decompile.json`、`native-0x69fc.json`、`native-0x6c2c.json`、`native-0x6f34.json`。后三份保存完整 MCP JSON-RPC 响应；Evidence 位于 `result.structuredContent`。

下列是对控制流的概念重述，非可编译源码：

```text
scan(cacheRoot):
  ignore = OR(dsStoreNamePredicate, knowledgeBaseIgnore)
  candidates = contents(cacheRoot)
  if cancelled: return emptyResult
  for item in candidates:
    waitWhilePaused()
    if cancelled or ignore(item): skip/stop
    if knowledgeBase.shouldPerformDeepSearch(item.lastPathComponent):
      result = group(filtered and measured immediate children)
    else:
      bytes = fileSizer(item, cancellation)
      if bytes == 0 and not readable(item) and helperAuthorized:
        bytes = helper.fileSize(item)
      if not cancelled and (helperAuthorized or bytes != 0):
        result = FileModel(item, bytes, task.isResultAutoselectable)
```

## 对自研的实际意义

1. 规则、目录遍历、空间计量、结果模型、选择策略需要分离；不宜把路径数组直接交给递归删除。
2. Deep search 不是“扫描得越深越好”：它是知识库决定的分组精度。默认整目录处理会改变保护边界。
3. 自动勾选来自 task 属性；这里没有证明所有缓存安全或都默认勾选。
4. 原实现有把取消/不可计量返回为 0 的路径。自研应保留状态，不能将 0 一概解释为空目录。
5. 普通权限与 helper fallback 分离。自研第一版可先报告权限盲区，而不是默认要求 root。

## 可重复性与限制

独立命令示例（目录须已存在；只针对分析副本）：

```sh
GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec \
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
rea decompile /Users/leozhou/git/clean-my-mac/.local/binaries/SystemJunkScanning.arm64 \
  0x672c --provider ghidra --json
```

批量后续查询通过同一 REA MCP stdio session 完成，最后 `close_binary` 保存 `.local/evidence/cache-session-snapshot.json`；关闭回执在 `native-close.json`。这是可重用查询证据快照，不是完整 Ghidra 工程数据库。

Ghidra 输出含 ObjC retain/release fixup 与 terminal-call 限制；部分参数类型与调用签名未可靠恢复。结论由结构控制流与独立 llvm-objdump 汇编交叉支撑，仍不证明本机扫描结果、性能、完整规则库或全局删除安全性。
