import Foundation

/// 容错 JSON 读取：未知字段忽略，字段缺失/类型不符返回 nil，绝不抛错。
/// 体检解码统一走这里，保证"关键字段缺失 → 降级 rawText"的协议。
public enum LenientJSON {
  /// 把文本解析为顶层 JSON 值；解析失败返回 nil。
  public static func parse(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  public static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
  public static func array(_ value: Any?) -> [Any]? { value as? [Any] }

  public static func string(_ value: Any?, key: String) -> String? {
    object(value)?[key] as? String
  }
  public static func bool(_ value: Any?, key: String) -> Bool? {
    object(value)?[key] as? Bool
  }
  public static func double(_ value: Any?, key: String) -> Double? {
    if let n = object(value)?[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return nil
  }
  /// 整数字段；布尔不是数字（NSNumber 布尔要排除）。
  public static func int(_ value: Any?, key: String) -> Int? {
    if let n = object(value)?[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    return nil
  }

  // MARK: - 面向已解包字典的便捷读取
  public static func string(_ dict: [String: Any], _ key: String) -> String? { dict[key] as? String }
  public static func bool(_ dict: [String: Any], _ key: String) -> Bool? { dict[key] as? Bool }
  public static func double(_ dict: [String: Any], _ key: String) -> Double? {
    if let n = dict[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return nil
  }
  public static func int(_ dict: [String: Any], _ key: String) -> Int? {
    if let n = dict[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    return nil
  }
  public static func strings(_ dict: [String: Any], _ key: String) -> [String] {
    (dict[key] as? [Any])?.compactMap { $0 as? String } ?? []
  }
  public static func objects(_ dict: [String: Any], _ key: String) -> [[String: Any]] {
    (dict[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
  }
}
