# 实施决定与最终源码快照

2026-10-12最终交付快照。无commit revision，用逐文件SHA256绑定；源文件变更需重验。

- 保留基线PRD/契约：生产执行关闭，缓存seed只previewOnly，activity unknown不得变inactive。T09调查DONE，准入0/2，AC-09/M2 BLOCKED。
- M0/M1真实代码与部分宿主证据已交，但完整AC未齐仍DOING。Release可启动不等v1完成；T24制品已交而前置安全验收BLOCKED。
- internal fixture原型资格使用token+device/inode+0700/no-follow marker校验；无生产CLI/API绕过路径。绝不把原型当完整Transaction/Recovery。
- 独立review发现仓库保护绕过：增加.git目录/worktree文件、根与scope外祖先metadata-only检测；Preflight新增仓库祖先后拒绝旧计划。定向fixture测试通过，最终独立review 3 HIGH已修正，APPROVE仅对Gate=false交付，不替M2验收。
- 最小窗口UI失败保留：外部应用窗口打断；测试启动后activate本App修复，无其他app关闭。最终2项UI测试通过，但VoiceOver/完整生命周期/全执行链未验证。
- 早期Trash真实fixture变更后收据丢失/teardown缺陷已记录，不以新拒绝路径PASS抹除。后续先能力预检、返回URL先durable unknown记录、未对账不teardown。系统Trash完整链仍EPERM BLOCKED；遗留清单不完整。
- 三错误变体在独立副本中被断言检出；不合入产品、不以局部检测代替整AC。所有失败日志保留。
- 性能固定100×500个1KiB文件，warm/uncontrolled cache，不用purge制造冷启动；主线程busy指标未测保持UNVERIFIED，不降低100ms预算。

Release manifest sourceSHA256与本快照逐项匹配：True. 独立plan向量：plan-vector-v1.json SHA256 `97d78f6e8f5f77c8b327a2d18c4f88d873c8194b97421ea848c38c6aef3057e8`；规则/fixture版本以下列hash绑定。

## SHA256

- `App/.DS_Store`：`7e24b58f70b2f29b5d1fdab916386092b4a7ec4342003d5ada15c7ba8292f189`
- `App/LocalMacCleaner/LocalMacCleanerApp.swift`：`1c90514106af15dca30076a38b8f49b88a5ba959ced8773af4792f7016acd0ad`
- `App/LocalMacCleaner.xcodeproj/project.pbxproj`：`b149588ff9f592d44f82244a58f2af097fd45952a0a094b5bb74ed63f12437ad`
- `App/LocalMacCleaner.xcodeproj/xcshareddata/xcschemes/LocalMacCleaner.xcscheme`：`10b6527187ade52fcc2b87ea8fef5da47c88baaa872306b8cc55b9fd0d69ae10`
- `App/LocalMacCleanerUITests/LocalMacCleanerUITests.swift`：`8526f2aafcf8374804ee39cbc22c3f8416d0c7d0a70cce4f0ca989ed0d673eab`
- `Package.swift`：`d335f04daa4baa688c572f8bd9c723fb0163e5256f05568ee8abce1549eb8f86`
- `Resources/Rules/seed-v1.json`：`9dc7eeed1cff6a68f5312a34b91b0869a7ff6fadd59d20a5aed3ee6982f73332`
- `Sources/.DS_Store`：`31c358ce4a5d55bd68fbafebb366ca764bac7b1096dff84477272bd14d573927`
- `Sources/CSQLite/module.modulemap`：`bbfe59a972a3e8e09e347c04bc22c0eacd2544881af8a4b6068bfc30b38466e8`
- `Sources/CSQLite/shim.h`：`b052d8e561e942f97b503033ecd2eaa2b35213bdbf374983efe9e68eabdfc024`
- `Sources/CleanerCLI/main.swift`：`24ac87b6286d8393be379843a7928e7b86d1aa1b37ca21d2ca0667e5b3858fdd`
- `Sources/CleanerCore/Planning.swift`：`2512077aca11f11a56946192ee8b2a4a305a57747e86585a11ffab16eb0e6e83`
- `Sources/CleanerCore/Rules.swift`：`a7b52dd0ae3d5150f11c1e748167414923b914fbd1c5489e1ad3048cbe06f012`
- `Sources/CleanerDomain/Models.swift`：`53c3e07f74b36a0933cb751a435b57de2834ab4be18c3ee1b1720b93788ceab8`
- `Sources/CleanerExecution/AnchoredProbe.swift`：`4d2eb60d370b8e3411c8bff330a04ab37973d29c10a9db7ac9bb18173c7f7ebe`
- `Sources/CleanerExecution/Gate.swift`：`5cfa4697bf7a2a72035632dba1a5e21e08b09068d826aba7d26025bd7a703904`
- `Sources/CleanerExecution/ProbeAuthorization.swift`：`8a0895d74ae8590701e53ceeadd20d2cf98ea90ec60ca7c81c499eb0cedbfa0b`
- `Sources/CleanerExecution/PrototypeJournal.swift`：`78d7cd4562f4afb04c8d5ab5faacdf1e2849870db3612f353dbc2b218910754f`
- `Sources/CleanerMacPlatform/Activity.swift`：`d8f5dcfe995f612a746c9ebfd6f25a263e2f6717cf456ee9ca436b66724fbe69`
- `Sources/CleanerMacPlatform/FileReader.swift`：`5b120870d8065602242e49e77f9058d093fe48365ef20d1fe22fcf51b9719762`
- `Sources/CleanerMacPlatform/Preflight.swift`：`6f77d6c5dd397bbc44af8a2ac310d9762e06ec8421fe092a74eebce9282b67a3`
- `Sources/CleanerMacPlatform/SQLiteScanStore.swift`：`e3fe4197a10f8bf451319f6a9f669a737d39def869a9dbb0305b573915674bfd`
- `Sources/CleanerMacPlatform/ScanCoordinator.swift`：`c3eff175248db4f23803d9de626f76a01ade2bd7d5030ef972687642345a18e0`
- `TestSupport/Fixture.swift`：`5bef5efab6313720eb92ed2fc83a23d1be7359f1336e59bf1fd4eccf20075a0b`
- `TestSupport/plan-vector-v1.json`：`97d78f6e8f5f77c8b327a2d18c4f88d873c8194b97421ea848c38c6aef3057e8`
- `TestSupport/plan-vector-v1.sha256`：`0c96495bb127f9129ba175c0d961f0d6eb0c8923edb3f6ca1b7a6ed5e239859c`
- `Tests/.DS_Store`：`36141cffdda7114199ba1ed08edeb5a3cd697ceb5001c1763807e53b2a80a29c`
- `Tests/CleanerCoreTests/CoreTests.swift`：`ffc5401f2eb1c4e82a4db5c47d390e46ba98aa5f8f862d38603dfbf9470d1728`
- `Tests/CleanerExecutionTests/AnchoredProbeTests.swift`：`7a9c07c3e96fa53ce05e5572b423651aa5e1e78edfc479de6abeb1f4c93cf1e4`
- `Tests/CleanerExecutionTests/AuthorizationTests.swift`：`bafb3c727a9589f00017334828712a666f66cf489e741b49721e934b2e66ff72`
- `Tests/CleanerExecutionTests/PrototypeJournalTests.swift`：`dc7f9f61247c038b9df00b4f6b6ef3e7541217c1b2d53dfa004e42b177cf70c0`
- `Tests/CleanerExecutionTests/PrototypeTrashTests.swift`：`140b1fd06dbfc8df3733f680ea5394f3580ee607c82cc0f259a269aa18722774`
- `Tests/CleanerPlatformTests/BenchmarkTests.swift`：`fb2f0e4fcbbbbc960028e898eba1b3be2d09b63c6e94f996fccd465c0ada741f`
- `Tests/CleanerPlatformTests/PlatformTests.swift`：`4236c50a48f5612d26b43318c8150f6fcffe377a4aad5d62553fda3b06e2f03d`
- `Tests/CleanerPlatformTests/PreflightTests.swift`：`67babd54b49b1ade98d10612f765b6b165fb6166c1f870395d4c642a92580751`
- `scripts/build-app.sh`：`a486769fae61e41d25c1ad0045d2a011739dbdd80c393762e8db44a51b31db64`
- `scripts/cli-smoke.py`：`5138b4ad50ebae3519cee3fa2cbcdb33b37832a76b974ef0b7ed4fdd7e4bb5a1`
- `scripts/mutation-check.py`：`730ca9e09e9e07ff60223520b2b15191772401267b6bb659918a6949e7569c4b`
- `scripts/rule-admission-probe.sh`：`6043729e8f13e821fa824c0c8f80eec6e924c2076d0b3500c4d3f09eacc442ff`
