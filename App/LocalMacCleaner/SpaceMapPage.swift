import SwiftUI
import CleanerDomain
import CleanerViz

/// 空间地图 v2 页：全页 squarified treemap；点击目录下钻、面包屑跳级、前进/后退、
/// 悬停详情、文件详情面板、列表模式、重扫确认。只查询/渲染当前层 ≤30 瓦片 + “其他”。
struct SpaceMapPage: View {
    @Bindable var model: CleanerModel
    @State private var mapModel = SpaceMapModel()
    @State private var confirmRescan = false
    @State private var hoveredTile: SpaceMapModel.Tile?
    private let accent = Color.teal

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            Divider()
            if model.run == nil && !model.scanning { guide }
            else { content }
        }
        .overlay(alignment: .top) {
            if mapModel.loading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("查询当前层…").font(.caption2).foregroundStyle(.secondary) }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2).padding(.top, 8).allowsHitTesting(false)
            }
        }
        .task(id: taskKey) { await mapModel.reload(from: model) }
        .onChange(of: model.scanning) { _, scanning in if !scanning { mapModel.requestRefresh() } }
        .confirmationDialog("重新扫描将丢弃当前结果", isPresented: $confirmRescan, titleVisibility: .visible) {
            Button("重新扫描", role: .destructive) { model.startScan() }
            Button("取消", role: .cancel) {}
        } message: { Text("空间地图会随新结果自动重置到扫描根目录。") }
    }
    /// task 重查触发键：扫描 ID（换扫描/恢复快照重置到根）+ 导航令牌（下钻/回退/刷新）。
    private var taskKey: String { "\(model.run?.id.uuidString ?? "none")#\(mapModel.navigationToken)" }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "internaldrive.fill").font(.system(size: 22)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.volume?.name ?? "卷信息未知").font(.headline)
                    if let volume = model.volume, let capacity = volume.capacityBytes {
                        Text("容量 \(bytes(capacity)) · 可用 \(volume.availableBytes.map(bytes) ?? "未知")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("显示", selection: Binding(get: { mapModel.mode }, set: { mapModel.mode = $0 })) {
                    ForEach(SpaceMapModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 118).accessibilityIdentifier("spacemap.mode")
                Button { mapModel.requestRefresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(mapModel.loading).accessibilityIdentifier("spacemap.refresh").help("刷新当前层")
                Button("重新扫描") { confirmRescan = true }
                    .disabled(model.scanning || model.preparingIndex || model.scope == nil || model.indexPreparationError != nil)
                    .accessibilityIdentifier("spacemap.rescan").help("重新扫描将丢弃当前结果")
            }
            if model.scanning {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("扫描进行中，地图显示已提交部分，完成后自动刷新") }
                    .font(.caption).foregroundStyle(.secondary)
            }
            navigationBar
            if let error = mapModel.loadError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
    }
    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button { mapModel.back() } label: { Image(systemName: "arrow.left") }
                .disabled(!mapModel.canBack).accessibilityIdentifier("map.back").help("后退")
            Button { mapModel.forward() } label: { Image(systemName: "arrow.right") }
                .disabled(!mapModel.canForward).accessibilityIdentifier("map.forward").help("前进")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(mapModel.levels.enumerated()), id: \.offset) { position, level in
                        if position > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                        Button(level.name) { mapModel.jump(to: position) }
                            .buttonStyle(.plain).font(.caption)
                            .foregroundStyle(position == mapModel.index ? .primary : .secondary)
                            .accessibilityIdentifier("map.breadcrumb.\(position)")
                    }
                }
            }
        }
    }

    // MARK: 主体

    private var content: some View {
        HStack(alignment: .top, spacing: 0) {
            Group { if mapModel.mode == .treemap { treemapPane } else { listPane } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let entry = mapModel.focused { detailPane(entry).frame(width: 252).padding(.vertical, 14).padding(.trailing, 16) }
        }
    }

    private var treemapPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.25))
                    if mapModel.tiles.isEmpty && !mapModel.loading {
                        Text(mapModel.loadError == nil ? "本层暂无已知非零分配大小" : "查询失败，请刷新重试")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: size.width, height: size.height)
                            .accessibilityIdentifier("spacemap.empty")
                    }
                    ForEach(mapModel.tiles) { tile in
                        tileView(tile, size: size)
                            .offset(x: tile.unitRect.minX * size.width, y: tile.unitRect.minY * size.height)
                    }
                    if let hovered = hoveredTile { hoverCard(hovered).padding(8) }
                }
                // 容器不设 accessibilityIdentifier：会覆盖子瓦片的 map.tile.* 标识（SwiftUI 扁平化行为）
            }
            Text("本层合计 \(bytes(mapModel.levelTotalBytes)) · \(mapModel.tiles.count) 个瓦片 · 面积按 log₂ 压缩权重（指数 4），悬停查看真实字节与占比；计量去重（硬链接只计一次），“其他”含未入围与未取回项。")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16)
        }.padding(16)
    }

    private func tileView(_ tile: SpaceMapModel.Tile, size: CGSize) -> some View {
        let width: CGFloat = max(0, tile.unitRect.width * size.width)
        let height: CGFloat = max(0, tile.unitRect.height * size.height)
        let hovered: Bool = hoveredTile?.id == tile.id
        return Button(action: { tap(tile) }) { tileLabel(tile, width: width, height: height) }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { hoveredTile = tile } else if hoveredTile?.id == tile.id { hoveredTile = nil }
            }
            .contextMenu {
                if let entryID = tile.entryID, let entry = mapModel.entry(for: entryID) {
                    Button("在 Finder 中显示") { model.reveal(entry) }
                }
            }
            .accessibilityIdentifier("map.tile.\(tile.entryID?.uuidString ?? "other")")
            .accessibilityLabel("\(tile.name)，\(bytes(tile.bytes))")
            .help("\(tile.name) · \(bytes(tile.bytes))" + (tile.isDirectory ? " · 点击进入" : ""))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(hovered ? accent : .clear, lineWidth: 2))
    }
    private func tileLabel(_ tile: SpaceMapModel.Tile, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if width >= 40 && height >= 24 {
                Text(tile.name).font(.caption2.bold()).lineLimit(1).truncationMode(.middle)
                Text((tile.partial ? "已知 " : "") + bytes(tile.bytes) + (tile.partial ? "＋未知" : ""))
                    .font(.system(size: 9)).monospacedDigit().lineLimit(1)
            }
        }
        .padding(5)
        .frame(width: max(0, width - 3), height: max(0, height - 3), alignment: .topLeading)
        .background(tileFill(tile), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary, lineWidth: 1))
    }
    private func tap(_ tile: SpaceMapModel.Tile) {
        if tile.isDirectory { mapModel.enter(tile) }
        else if tile.id != .other { mapModel.focus(tile) }
    }
    /// 目录 teal / 文件蓝系；同层按大小次序渐变（最大最饱和），与 App teal 强调色协调。
    private func tileFill(_ tile: SpaceMapModel.Tile) -> Color {
        if tile.id == .other { return Color.gray.opacity(0.4) }
        let rank = Double(mapModel.tiles.firstIndex(where: { $0.id == tile.id }) ?? 0)
        let count = Double(max(1, mapModel.tiles.count - 1))
        let fade = count > 0 ? rank / count : 0
        return tile.isDirectory ? accent.opacity(0.85 - 0.5 * fade) : Color.blue.opacity(0.68 - 0.4 * fade)
    }
    private func hoverCard(_ tile: SpaceMapModel.Tile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.name).font(.caption.bold()).lineLimit(1)
            Text("\(bytes(tile.bytes)) · 占本层 \(String(format: "%.1f%%", tile.share * 100))").font(.caption2).monospacedDigit()
            if tile.partial { Text("目录计量含未知部分").font(.caption2).foregroundStyle(.secondary) }
            if tile.id == .other {
                Text(mapModel.otherCount > 0 || mapModel.truncated
                     ? "本层未入围项合计（\(mapModel.otherCount) 项小项\(mapModel.truncated ? " + 未取回项" : "")）"
                     : "当前层条目均未单独计入（共享或过小）")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let mtime = tile.mtime { Text("修改 " + mtime.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8).frame(maxWidth: 250, alignment: .leading)
        .background(.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .shadow(radius: 3)
        .allowsHitTesting(false)
        .accessibilityIdentifier("spacemap.hover")
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Table(mapModel.rows) {
                TableColumn("名称") { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.identity?.kind == .directory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.identity?.kind == .directory ? accent : .secondary)
                        Text(SpaceMapModel.displayName(entry)).lineLimit(1).help(entry.relativePath)
                    }
                }
                TableColumn("大小") { entry in Text(listSize(entry)).font(.caption).monospacedDigit() }.width(120)
                TableColumn("类型") { entry in Text(kindText(entry)).font(.caption) }.width(80)
                TableColumn("修改时间") { entry in
                    Text(SpaceMapModel.modified(entry).map { $0.formatted(date: .numeric, time: .shortened) } ?? "未知").font(.caption)
                }.width(130)
            }
            .accessibilityIdentifier("spacemap.table")
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let entry = mapModel.entry(for: id) { Button("在 Finder 中显示") { model.reveal(entry) } }
            } primaryAction: { ids in
                if let id = ids.first, let entry = mapModel.entry(for: id) { mapModel.focusEntry(entry) }
            }
            Text(mapModel.truncated ? "仅显示本层最大的前 \(SpaceMapModel.fetchLimit) 项" : "本层共 \(mapModel.rows.count) 项")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func listSize(_ entry: Entry) -> String {
        let weight = mapModel.weight(of: entry.id)
        if entry.identity?.kind == .directory {
            let known = weight ?? entry.allocatedBytes?.value ?? 0
            return entry.measureState != .measured ? (known > 0 ? "已知 \(bytes(known))＋未知" : "未知") : bytes(known)
        }
        if let raw = entry.allocatedBytes?.value, raw > 0, weight == 0 { return bytes(raw) + " · 共享已另计" }
        return bytes(weight ?? entry.allocatedBytes?.value ?? 0)
    }
    private func kindText(_ entry: Entry) -> String {
        switch entry.identity?.kind { case .directory: "目录"; case .regular: "文件"; case .symlink: "符号链接"; case .other, nil: "其他" }
    }

    private func detailPane(_ entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(SpaceMapModel.displayName(entry)).font(.headline)
                Text(entry.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text(entry.decision.reason).font(.callout)
                LabeledContent("规则", value: entry.decision.ruleIDs.isEmpty ? "—" : entry.decision.ruleIDs.joined(separator: "、")).font(.caption)
                LabeledContent("所属", value: entry.decision.owner).font(.caption)
                LabeledContent("分配", value: entry.allocatedBytes.map { bytes($0.value) } ?? "未知").font(.caption)
                LabeledContent("逻辑", value: entry.logicalBytes.map { bytes($0.value) } ?? "未知").font(.caption)
                if let weight = mapModel.weight(of: entry.id), mapModel.levelTotalBytes > 0 {
                    LabeledContent("占本层", value: String(format: "%.1f%%", Double(weight) / Double(mapModel.levelTotalBytes) * 100)).font(.caption)
                }
                if let mtime = SpaceMapModel.modified(entry) { LabeledContent("修改时间", value: mtime.formatted(date: .numeric, time: .shortened)).font(.caption) }
                if entry.identity?.kind == .regular, let raw = entry.allocatedBytes?.value, raw > 0, mapModel.weight(of: entry.id) == 0 {
                    Text("共享对象：已在另一路径计量，地图中分配为 0。").font(.caption).foregroundStyle(.secondary)
                }
                Button("在 Finder 中显示") { model.reveal(entry) }.accessibilityIdentifier("spacemap.reveal")
                if entry.identity?.kind == .directory, let tile = mapModel.tiles.first(where: { $0.entryID == entry.id }) {
                    Button("进入这个目录") { mapModel.enter(tile) }.accessibilityIdentifier("detail.enter")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 引导态

    private var guide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从哪里开始？").font(.headline)
            Text("空间地图按层展示扫描结果：点击目录瓦片下钻，面包屑跳级，前进/后退随时回溯。先完成一次扫描，即可看到全页树图。")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
            HStack(spacing: 10) {
                Button("扫描内置存储") { model.quickScan(.internalDisk) }.disabled(model.preparingIndex || model.indexPreparationError != nil)
                Button("扫描我的文件") { model.quickScan(.home) }.disabled(model.preparingIndex || model.indexPreparationError != nil)
                Button("扫描下载") { model.quickScan(.downloads) }.disabled(model.preparingIndex || model.indexPreparationError != nil)
            }
            if model.preparingIndex { HStack { ProgressView().controlSize(.small); Text("正在准备本地索引…") }.font(.caption).foregroundStyle(.secondary) }
            if let failure = model.indexPreparationError { Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}
