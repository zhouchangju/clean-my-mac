import XCTest

final class LocalMacCleanerUITests: XCTestCase {
    @MainActor
    private func text(_ element: XCUIElement) -> String { element.value as? String ?? element.label }
    @MainActor
    private func launch(_ arguments: [String] = [], waitForReady: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lmcUITest"] + arguments
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["scope.internalDisk"].waitForExistence(timeout: 15))
        if waitForReady {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["scan.start"])
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
            XCTAssertFalse(app.staticTexts["index.failed"].exists)
        }
        return app
    }
    @MainActor
    private func scan(_ app: XCUIApplication, button: String = "scope.internalDisk") {
        app.buttons[button].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        let status = text(app.staticTexts["scan.status"])
        if app.launchArguments.contains("-lmcEmptyFixture") { XCTAssertTrue(status.contains("扫描完成"), status) }
        else { XCTAssertTrue(status.contains("部分结果") && status.contains("32 项"), "fixture 的 .git 元数据保护不深入，预期32项partial：" + status) }
        XCTAssertFalse(app.dialogs.firstMatch.exists, "快捷扫描不能出现范围选择面板")
    }
    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String, scopeActionAvailable: Bool = true) {
        app.activate()
        if scopeActionAvailable { XCTAssertTrue(app.buttons["scope.choose"].isHittable) }
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    func testScanWaitNoticeAndStopDuringPreparation() throws {
        let app = launch(["-lmcLight", "-lmcStalledScanFixture"])
        app.buttons["scope.internalDisk"].click()
        let notice = app.staticTexts["scan.waitingForSystem"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(text(notice).contains("应用不会自动授权"))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        snapshot(app, "扫描等待系统响应提示", scopeActionAvailable: false)
        app.buttons["scan.cancel"].click()
        let stopping = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "停止请求仍在等待", "停止请求仍在等待"), object: notice)
        XCTAssertEqual(XCTWaiter.wait(for: [stopping], timeout: 3), .completed)
        XCTAssertFalse(app.buttons["scan.cancel"].isEnabled)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["scan.start"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 40), .completed)
        XCTAssertFalse(notice.exists)
        XCTAssertFalse(app.staticTexts["scan.status"].exists, "准备期间取消不能假造一次扫描终态")
        app.terminate()
        let ordinary = launch(["-lmcLight"])
        scan(ordinary)
        XCTAssertFalse(ordinary.staticTexts["scan.waitingForSystem"].exists, "正常完成后没有等待提示")
        ordinary.terminate()
    }
    @MainActor
    func testStorageHeaderVisibleAtBothSizesAndThemes() throws {
        for arguments in [["-lmcLight"], ["-lmcDark"], ["-lmcLight", "-lmcSmallWindow"], ["-lmcDark", "-lmcSmallWindow"]] {
            let app = launch(arguments)
            let window = app.windows.firstMatch
            let title = app.staticTexts["storage.pageTitle"]
            XCTAssertTrue(title.isHittable)
            for identifier in ["scope.choose", "scan.start", "scope.internalDisk", "scope.home", "scope.downloads"] {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.isHittable, identifier)
                XCTAssertTrue(window.frame.contains(button.frame), "完整操作区必须在窗口内：" + identifier)
            }
            XCTAssertTrue(window.frame.contains(title.frame), "完整标题必须在窗口内")
            snapshot(app, "存储页完整标题与操作区 " + arguments.joined(separator: " "))
            app.terminate()
        }
    }
    @MainActor
    func testRealDashboardMapAndPlan() throws {
        let app = launch(["-lmcLight"])
        XCTAssertTrue(app.buttons["scan.start"].isEnabled, "首次已预选内置存储")
        XCTAssertFalse(app.staticTexts["scan.status"].exists, "首次不会自动扫描")
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        snapshot(app, "1180×780 浅色首次看板")
        scan(app)
        XCTAssertTrue(text(app.staticTexts["dashboard.knownBytes"]).contains("MB"), "真实fixture已知分配非零")
        XCTAssertTrue(app.buttons["dashboard.category.downloads"].exists)
        XCTAssertTrue(app.buttons["insight.largeFiles"].exists)
        snapshot(app, "真实扫描分类看板")
        app.staticTexts["navigation.空间地图"].click()
        let mapTile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "map.tile.", "Downloads")).firstMatch
        XCTAssertTrue(mapTile.waitForExistence(timeout: 10))
        mapTile.click()
        XCTAssertTrue(app.buttons["map.breadcrumb.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["map.back"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "spacemap.mode").firstMatch.exists)
        snapshot(app, "同层地图与Downloads下钻")
        app.buttons["map.breadcrumb.0"].click()
        XCTAssertFalse(app.buttons["map.back"].isEnabled)
        app.staticTexts["navigation.文件浏览"].click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "results.table").firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["navigation.大文件"].click()
        let checkbox = app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.select.")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10)); XCTAssertTrue(checkbox.isEnabled)
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        checkbox.click()
        XCTAssertTrue(app.buttons["plan.preview"].isEnabled)
        app.buttons["plan.preview"].click()
        XCTAssertTrue(app.buttons["plan.confirmTrash"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["plan.confirmTrash"].isEnabled)
        snapshot(app, "真实预检与锁定执行")
        app.buttons["plan.close"].click()
        app.staticTexts["navigation.整理建议"].click()
        XCTAssertTrue(app.buttons["recommendation.下载整理"].waitForExistence(timeout: 10))
        app.buttons["recommendation.下载整理"].click()
        XCTAssertTrue(app.textFields["results.search"].exists)
        snapshot(app, "分类整理建议")
    }
    @MainActor
    func testSmallDarkKeyboardSearchAndSort() throws {
        let app = launch(["-lmcDark", "-lmcSmallWindow"])
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 1000)
        XCTAssertLessThanOrEqual(app.windows.firstMatch.frame.width, 1020)
        XCTAssertTrue(app.buttons["scope.internalDisk"].isHittable)
        XCTAssertTrue(app.buttons["scope.home"].isHittable)
        XCTAssertTrue(app.buttons["scope.downloads"].isHittable)
        scan(app, button: "scope.home")
        app.staticTexts["navigation.文件浏览"].click()
        XCTAssertTrue(app.buttons["plan.preview"].isHittable)
        let sort = app.popUpButtons["results.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        sort.click(); app.menuItems["逻辑大小"].click()
        let search = app.textFields["results.search"]
        app.typeKey("f", modifierFlags: .command); search.typeText("no-match-fixture")
        XCTAssertTrue(app.staticTexts["results.empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["plan.preview"].isHittable)
        snapshot(app, "1000×680 深色键盘空筛选")
    }
    @MainActor
    func testEmptyFixtureQuickDownloads() throws {
        let app = launch(["-lmcLight", "-lmcEmptyFixture"])
        scan(app, button: "scope.downloads")
        XCTAssertTrue(text(app.staticTexts["dashboard.knownBytes"]).contains("0"))
        app.staticTexts["navigation.文件浏览"].click()
        XCTAssertTrue(app.staticTexts["results.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        snapshot(app, "真实空目录结果")
    }
    @MainActor
    func testQuotaStopsWithUnknownCoverage() throws {
        let app = launch(["-lmcLight", "-lmcQuotaFixture"])
        app.buttons["scope.internalDisk"].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        XCTAssertTrue(text(app.staticTexts["scan.status"]).contains("部分结果"))
        XCTAssertTrue(app.staticTexts["scan.stopReason"].exists)
        XCTAssertTrue(text(app.staticTexts["dashboard.knownBytes"]).contains("未成功计量"))
        XCTAssertTrue(text(app.staticTexts["dashboard.measureState"]).contains("不能把未读取范围当成空目录"))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        XCTAssertTrue(app.staticTexts["dashboard.categoriesUnknown"].exists)
        snapshot(app, "索引配额停止·未知覆盖")
    }
    @MainActor
    func testRescanRetiresOnlyOldOwnIndex() throws {
        let app = launch(["-lmcLight", "-lmcEmptyFixture"])
        scan(app)
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        XCTAssertTrue(text(app.staticTexts["scan.status"]).contains("扫描完成"))
        XCTAssertTrue(text(app.staticTexts["scan.maintenanceNotice"]).contains("已整理旧扫描索引"))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
    }

    @MainActor
    func testPendingOwnStateSkipsIndexRetirement() throws {
        let app = launch(["-lmcLight", "-lmcEmptyFixture", "-lmcPendingFixture"])
        scan(app)
        XCTAssertTrue(text(app.staticTexts["scan.maintenanceNotice"]).contains("已保守保留全部旧索引"))
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        XCTAssertTrue(text(app.staticTexts["scan.maintenanceNotice"]).contains("已保守保留全部旧索引"))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
    }

    @MainActor
    func testDeniedDirectoriesRemainUnknownAndSparseFileKeepsZero() throws {
        let app = launch(["-lmcLight", "-lmcDeniedFixture", "-lmcEmptyFixture"])
        app.buttons["scope.internalDisk"].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        XCTAssertTrue(text(app.staticTexts["scan.status"]).contains("部分结果"))
        let deniedFolder = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.folder.")).firstMatch
        XCTAssertTrue(deniedFolder.waitForExistence(timeout: 10))
        XCTAssertTrue(deniedFolder.label.contains("未知"), deniedFolder.label)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
        snapshot(app, "无权限目录看板未知")
        app.staticTexts["navigation.文件浏览"].click()
        let allocated = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.allocated.")).firstMatch
        let logical = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.logical.")).firstMatch
        XCTAssertTrue(allocated.waitForExistence(timeout: 10)); XCTAssertEqual(text(allocated), "未知")
        XCTAssertEqual(text(logical), "未知")
        snapshot(app, "无权限目录两种计量均未知")
        app.launchArguments = ["-lmcUITest", "-lmcLight"]
        app.launch(); app.activate()
        scan(app)
        app.staticTexts["navigation.大文件"].click()
        XCTAssertTrue(allocated.waitForExistence(timeout: 10))
        XCTAssertTrue(text(allocated).contains("0")); XCTAssertFalse(text(allocated).contains("未知"))
        XCTAssertTrue(text(logical).contains("MB")); XCTAssertFalse(text(logical).contains("未知"))
        snapshot(app, "真实稀疏文件分配零但逻辑非零")
    }

    @MainActor
    func testCoalescedRefreshDropsStalePageAndScope() throws {
        let app = launch(["-lmcLight", "-lmcRefreshDelayFixture"])
        scan(app)
        let observer = app.staticTexts["test.refreshObserver"]
        XCTAssertTrue(observer.exists)
        app.activate()
        app.staticTexts["navigation.空间地图"].click()
        let active = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "当前刷新 1"), object: observer)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 10), .completed)
        app.activate()
        app.staticTexts["navigation.大文件"].click()
        let logical = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.logical.")).firstMatch
        XCTAssertTrue(logical.waitForExistence(timeout: 15))
        XCTAssertTrue(text(logical).contains("MB"))
        XCTAssertTrue(text(observer).contains("并行刷新峰值 1"))
        XCTAssertNotNil(text(observer).range(of: "丢弃旧视图 [1-9]", options: .regularExpression), text(observer))
        app.activate()
        app.staticTexts["navigation.空间地图"].click()
        let newActive = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "当前刷新 1"), object: observer)
        XCTAssertEqual(XCTWaiter.wait(for: [newActive], timeout: 10), .completed)
        app.buttons["scope.choose"].click()
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        XCTAssertFalse(app.staticTexts["scan.status"].exists)
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 30))
        XCTAssertTrue(text(observer).contains("并行刷新峰值 1"))
        XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
        snapshot(app, "真实SQLite延迟刷新·单任务与代次失效")
    }

    @MainActor
    func testBackgroundLegacyV4MigrationKeepsPreparationResponsive() throws {
        let app = launch(["-lmcLight", "-lmcMigrationFixture"], waitForReady: false)
        XCTAssertTrue(app.staticTexts["index.preparing"].exists)
        for identifier in ["scan.start", "scope.internalDisk", "scope.home", "scope.downloads"] { XCTAssertFalse(app.buttons[identifier].isEnabled) }
        app.activate()
        app.staticTexts["navigation.设置"].click()
        XCTAssertTrue(app.staticTexts["index.preparing"].exists, "真正v4迁移前等待窗口中页面仍可切换")
        snapshot(app, "真实旧v4索引准备期·页面可响应", scopeActionAvailable: false)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["scan.start"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts["index.preparing"].exists)
        let migrated = app.staticTexts["test.indexMigrationStatus"]
        XCTAssertTrue(migrated.exists)
        XCTAssertTrue(text(migrated).contains("3 项"))
        XCTAssertTrue(text(migrated).contains("2097152 字节"), text(migrated))
        app.staticTexts["navigation.存储看板"].click()
        scan(app)
        XCTAssertTrue(text(app.staticTexts["dashboard.knownBytes"]).contains("MB"))
        snapshot(app, "旧v4真实迁移完成·ready后实际扫描")
    }

    @MainActor
    func testRetainedSnapshotRestoresBrowseOnlyAndRejectsActiveOrReplacedScope() throws {
        for extra in [[], ["-lmcPartialSnapshotFixture"], ["-lmcActiveSnapshotFixture"], ["-lmcReplacedScopeFixture"]] {
            let app = launch(["-lmcLight", "-lmcMigrationFixture", "-lmcEligibleRestoreFixture"] + extra)
            let notice = app.staticTexts["scan.restoredSnapshot"]
            if extra.contains("-lmcActiveSnapshotFixture") || extra.contains("-lmcReplacedScopeFixture") {
                XCTAssertFalse(notice.exists)
                XCTAssertFalse(app.staticTexts["scan.status"].exists)
                if extra.contains("-lmcReplacedScopeFixture") {
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "身份已变化", "身份已变化")).firstMatch.exists)
                }
            } else {
                XCTAssertTrue(notice.waitForExistence(timeout: 15))
                XCTAssertTrue(text(notice).contains("上次扫描"))
                XCTAssertTrue(text(notice).contains("仅供浏览"))
                let status = app.staticTexts["scan.status"]
                XCTAssertTrue(status.exists)
                XCTAssertTrue(text(status).contains("4 项"), text(status))
                if extra.contains("-lmcPartialSnapshotFixture") {
                    XCTAssertTrue(text(status).contains("部分结果"))
                    XCTAssertTrue(app.staticTexts["scan.stopReason"].exists)
                }
                app.activate()
                app.staticTexts["navigation.空间地图"].click()
                let directory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "map.tile.", "Downloads")).firstMatch
                XCTAssertTrue(directory.waitForExistence(timeout: 15))
                directory.click()
                XCTAssertTrue(app.buttons["map.breadcrumb.1"].waitForExistence(timeout: 15))
                app.staticTexts["navigation.文件浏览"].click()
                let downloadsName = app.staticTexts.matching(NSPredicate(format: "value == %@", "Downloads")).firstMatch
                XCTAssertTrue(downloadsName.waitForExistence(timeout: 15))
                downloadsName.doubleClick()
                XCTAssertTrue(app.buttons["map.breadcrumb.1"].waitForExistence(timeout: 15))
                let item = app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.select.")).element(boundBy: 1)
                XCTAssertTrue(item.waitForExistence(timeout: 15))
                XCTAssertFalse(item.isEnabled)
                XCTAssertFalse(app.buttons["plan.preview"].isEnabled)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "已选 0 项", "已选 0 项")).firstMatch.exists)
                snapshot(app, extra.isEmpty ? "上次完整结果只读恢复" : "上次部分结果与缺口恢复")
                if extra.isEmpty {
                    app.activate()
                    app.buttons["scan.start"].click()
                    let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "32 项", "32 项"), object: app.staticTexts["scan.status"])
                    XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 30), .completed)
                    XCTAssertFalse(notice.exists)
                    app.activate()
                    app.staticTexts["navigation.大文件"].click()
                    let freshItem = app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.select.")).firstMatch
                    XCTAssertTrue(freshItem.waitForExistence(timeout: 15))
                    XCTAssertTrue(freshItem.isEnabled)
                    freshItem.click()
                    XCTAssertTrue(app.buttons["plan.preview"].isEnabled)
                    app.buttons["plan.preview"].click()
                    XCTAssertTrue(app.buttons["plan.confirmTrash"].waitForExistence(timeout: 15))
                    XCTAssertFalse(app.buttons["plan.confirmTrash"].isEnabled)
                }
            }
            app.terminate()
        }
    }

}
