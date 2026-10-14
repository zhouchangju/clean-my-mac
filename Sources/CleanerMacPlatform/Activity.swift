import CleanerDomain
/// No absence-of-window or process-name heuristic can prove a file is unused.
public enum ApplicationActivityProvider {
    public static func evaluate(owner: String) -> Activity { .unknown }
}
public extension Activity {
    static func evaluate(owner: String) -> Activity { ApplicationActivityProvider.evaluate(owner: owner) }
}
