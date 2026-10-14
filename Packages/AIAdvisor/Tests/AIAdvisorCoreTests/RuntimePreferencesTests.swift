import Foundation
import Testing
import AIAdvisorCore

/// 偏好读写与非法值容错（独立 UserDefaults suite，不污染宿主偏好）。
@Suite struct RuntimePreferencesTests {

    private func freshDefaults() throws -> UserDefaults {
        let suite = "lmc-air-prefs-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func writeAndReadRoundTrip() throws {
        let defaults = try freshDefaults()
        #expect(RuntimePreferences.writeDefault("codex", defaults: defaults) == true)
        #expect(RuntimePreferences.readDefault(defaults: defaults) == "codex")
    }

    @Test func readRejectsUnknownValue() throws {
        let defaults = try freshDefaults()
        defaults.set("not-a-runtime", forKey: AIRuntimePreferenceKey.defaultRuntime) // 直接塞非法值
        #expect(RuntimePreferences.readDefault(defaults: defaults) == nil) // 容错返回 nil
    }

    @Test func writeRejectsUnknownValue() throws {
        let defaults = try freshDefaults()
        #expect(RuntimePreferences.writeDefault("zzz", defaults: defaults) == false)
        #expect(defaults.string(forKey: AIRuntimePreferenceKey.defaultRuntime) == nil) // fail-closed：不落盘
    }

    @Test func writeNilClears() throws {
        let defaults = try freshDefaults()
        RuntimePreferences.writeDefault("opencode", defaults: defaults)
        #expect(RuntimePreferences.readDefault(defaults: defaults) == "opencode")
        RuntimePreferences.writeDefault(nil, defaults: defaults)
        #expect(RuntimePreferences.readDefault(defaults: defaults) == nil)
    }

    @Test func allCatalogIDsAreAccepted() throws {
        let defaults = try freshDefaults()
        for id in AIRuntimeCatalog.ids {
            #expect(RuntimePreferences.writeDefault(id, defaults: defaults))
            #expect(RuntimePreferences.readDefault(defaults: defaults) == id)
        }
    }
}
