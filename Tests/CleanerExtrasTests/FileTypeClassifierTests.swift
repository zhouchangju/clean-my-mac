import Foundation
import Testing
@testable import CleanerExtras

private let classifier = FileTypeClassifier()

@Test func classifierCoversEveryKindWithRepresentativeExtensions() {
    let cases: [(String, FileTypeClassifier.Kind)] = [
        ("song.mp3", .audio), ("photo.jpeg", .picture), ("clip.mov", .video), ("paper.pdf", .document),
        ("bundle.zip", .archive), ("Installer.dmg", .installer), ("llama-7b.gguf", .aiModel),
        ("model.safetensors", .aiModel), ("net.onnx", .aiModel), ("Vision.mlmodel", .aiModel), ("sd-v1.ckpt", .aiModel), ("weights.pt", .aiModel),
    ]
    for (name, expected) in cases { #expect(classifier.classify(path: name) == expected, "\(name)") }
}

@Test func classifierIsCaseInsensitiveAndTakesLastExtension() {
    #expect(classifier.classify(path: "MOVIE.MP4") == .video)
    #expect(classifier.classify(path: "Photo.HeIc") == .picture)
    #expect(classifier.classify(path: "backup.tar.gz") == .archive)      // 多点：只看最后一段
    #expect(classifier.classify(path: "report.final.v2.pdf") == .document)
    #expect(classifier.classify(path: "/Users/x/Downloads/a.b/c/d.flac") == .audio) // 目录名含点不干扰
    #expect(classifier.classify(extension: ".PNG") == .picture)
    #expect(classifier.classify(extension: "png") == .picture)
}

@Test func classifierReturnsEmptyForUnknownHiddenOrExtensionless() {
    #expect(classifier.classify(path: "Makefile").isEmpty)
    #expect(classifier.classify(path: ".gitignore").isEmpty)   // 隐藏文件：首位点不是扩展名分隔符
    #expect(classifier.classify(path: "name.").isEmpty)        // 末尾点：空扩展名
    #expect(classifier.classify(path: "thing.zzzunknown").isEmpty)
    #expect(classifier.classify(path: "").isEmpty)
    #expect(classifier.classify(extension: "").isEmpty)
    #expect(classifier.classify(extension: ".").isEmpty)
}

@Test func classifierDeliberatelyExcludesAmbiguousExtensions() {
    // .bin 泛指任意二进制，不归入 AI 模型，避免误报。
    #expect(classifier.classify(path: "pytorch_model.bin").isEmpty)
    // .ts 多为 TypeScript 源码；.key 可能是 TLS 私钥。
    #expect(classifier.classify(path: "app.ts").isEmpty)
    #expect(classifier.classify(path: "server.key").isEmpty)
}

@Test func classifierChineseTitlesComposeInBitOrder() {
    #expect(FileTypeClassifier.Kind.audio.chineseTitle == "音频")
    #expect(FileTypeClassifier.Kind.aiModel.chineseTitle == "AI 模型")
    #expect(FileTypeClassifier.Kind([]).chineseTitle == "其他")
    #expect(FileTypeClassifier.Kind([.video, .audio]).chineseTitle == "音频、视频") // 按位序，不按构造顺序
    #expect(FileTypeClassifier.Kind.all.count == 7)
    // 每个扩展名只命中一个位，且全表覆盖 7 类。
    var seen: FileTypeClassifier.Kind = []
    for (_, kind) in FileTypeClassifier.table { #expect(kind.rawValue.nonzeroBitCount == 1); seen.formUnion(kind) }
    #expect(seen == FileTypeClassifier.Kind(FileTypeClassifier.Kind.all))
}
