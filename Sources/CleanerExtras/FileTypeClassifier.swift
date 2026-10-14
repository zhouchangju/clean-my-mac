import Foundation

/// 文件类型分类器：仅凭扩展名把文件归入若干展示类别（位集），供大文件页/重复页过滤。
/// 纯函数、无 I/O、大小写不敏感；多点扩展名（a.tar.gz）只看最后一段；未知扩展名返回空集（UI 显示“其他”）。
/// 这是展示用启发式，不是内容嗅探——不得用它推断“可删除”。
public struct FileTypeClassifier: Sendable {
    /// 类型位集。单个扩展名只会命中一个位；组合值用于 UI 过滤条件。
    public struct Kind: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let audio     = Kind(rawValue: 1 << 0)
        public static let picture   = Kind(rawValue: 1 << 1)
        public static let video     = Kind(rawValue: 1 << 2)
        public static let document  = Kind(rawValue: 1 << 3)
        public static let archive   = Kind(rawValue: 1 << 4)
        public static let installer = Kind(rawValue: 1 << 5)
        /// AI 时代新增：本地推理/训练模型权重。
        public static let aiModel   = Kind(rawValue: 1 << 6)
        /// 全部已定义类别（按位序）。
        public static let all: [Kind] = [.audio, .picture, .video, .document, .archive, .installer, .aiModel]
        /// 中文标题；组合值按位序以“、”连接；空集为“其他”。
        public var chineseTitle: String {
            let parts = Kind.all.filter { contains($0) }.map(Kind.singleTitle)
            return parts.isEmpty ? "其他" : parts.joined(separator: "、")
        }
        private static func singleTitle(_ k: Kind) -> String {
            switch k {
            case .audio: "音频"; case .picture: "图片"; case .video: "视频"; case .document: "文档"
            case .archive: "压缩包"; case .installer: "安装包"; case .aiModel: "AI 模型"
            default: "其他"
            }
        }
    }

    public init() {}

    /// 扩展名（小写、不含点）→ 类别。集合取常见桌面格式；有争议者在注释说明取舍。
    static let table: [String: Kind] = {
        var t: [String: Kind] = [:]
        func put(_ kind: Kind, _ exts: [String]) { for e in exts { t[e] = kind } }
        put(.audio, ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "oga", "opus", "wma", "caf", "alac", "ape", "mid", "midi"])
        // psd/ai 虽为设计源文件，按“图片”归类更符合用户直觉；svg 是矢量图。
        put(.picture, ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "svg", "ico", "psd", "ai", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "avif", "jxl"])
        // 不收 .ts：TypeScript 源文件远多于 MPEG 传输流，误报代价高；m2ts/mts 足以覆盖摄像机素材。
        put(.video, ["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "mts", "m2ts", "vob", "ogv", "rm", "rmvb"])
        // iWork 文档包（.pages/.numbers）在磁盘上是目录，但按名字归类对展示仍有意义。
        // 不收 .key：与 TLS 私钥（server.key）同名，把凭据标成“文档”会误导用户。
        put(.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "rtfd", "pages", "numbers", "csv", "tsv", "epub", "mobi", "odt", "ods", "odp", "tex", "xmind"])
        // iso 是光盘镜像，归入压缩包而非安装包：它更接近“打包容器”，常见于系统镜像/资料归档。
        put(.archive, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "lz", "lzma", "z", "cab", "iso", "sit", "sitx", "jar", "war"])
        // dmg 是 macOS 安装介质的主要形态；ipa/apk 为移动端安装包。
        put(.installer, ["dmg", "pkg", "mpkg", "xip", "exe", "msi", "msix", "deb", "rpm", "appimage", "ipa", "apk"])
        // AI 模型：gguf(llama.cpp)/safetensors(HF)/onnx/mlmodel(CoreML)/ckpt/pt(PyTorch)。
        // 刻意不收 .bin：pytorch_model.bin 之外，bin 泛指任何二进制（固件、游戏资源、Git LFS 指针），误报率过高。
        put(.aiModel, ["gguf", "safetensors", "onnx", "mlmodel", "ckpt", "pt"])
        return t
    }()

    /// 按路径或文件名分类。隐藏文件（.gitignore）被视为无扩展名；末尾点（"name."）视为空扩展名。
    public func classify(path: String) -> Kind {
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
        return classify(extension: Self.extensionOf(name))
    }
    public func classify(url: URL) -> Kind { classify(path: url.path) }
    /// 直接按扩展名分类；接受带点或不带点、任意大小写。
    public func classify(extension raw: String) -> Kind {
        var e = raw.lowercased()
        if e.hasPrefix(".") { e.removeFirst() }
        guard !e.isEmpty else { return [] }
        return Self.table[e] ?? []
    }
    /// 取文件名最后一个点之后的部分；点在首位（隐藏文件）或不存在 → 空。
    static func extensionOf(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }
}
