import Foundation
import Darwin
import CleanerDomain

public struct StorageScopeProvider: Sendable {
    private let dataRoot: URL
    private let homeRoot: URL
    private let requireDataMount: Bool
    public init() {
        dataRoot = URL(fileURLWithPath:"/System/Volumes/Data",isDirectory:true)
        homeRoot = FileManager.default.homeDirectoryForCurrentUser
        requireDataMount = true
    }
    public init(dataRoot: URL, homeRoot: URL) { self.dataRoot=dataRoot; self.homeRoot=homeRoot; requireDataMount=false }
    public func scope(for preset: StorageScanPreset) throws -> ScanScope {
        let root: URL
        switch preset {
        case .internalDisk: root=dataRoot
        case .home: root=homeRoot
        case .downloads: root=homeRoot.appendingPathComponent("Downloads",isDirectory:true)
        case .custom: throw CleanerError(.invalidInput,"请通过目录选择器指定自选范围")
        }
        let scope = try MacFileReader().scope(path:root.path)
        if preset == .internalDisk {
            guard try volume(at:scope.rootPath).isInternal == true else { throw CleanerError(.unsupportedVolume,"无法确认此范围属于内置存储") }
            if requireDataMount {
                var fs = statfs()
                guard statfs(scope.rootPath,&fs)==0 else { throw CleanerError(.unsupportedVolume,"无法核实数据卷挂载") }
                let mount = withUnsafePointer(to:&fs.f_mntonname) { $0.withMemoryRebound(to:CChar.self,capacity:Int(MAXPATHLEN)) { String(cString:$0) } }
                guard mount == "/System/Volumes/Data" else { throw CleanerError(.unsupportedVolume,"内置数据卷挂载身份不符") }
            }
        }
        return scope
    }
    public func volume(at path: String) throws -> VolumeSnapshot {
        let url=URL(fileURLWithPath:path)
        let values=try url.resourceValues(forKeys:[.volumeNameKey,.volumeTotalCapacityKey,.volumeAvailableCapacityKey,.volumeIsInternalKey])
        return VolumeSnapshot(name:values.volumeName ?? "存储卷",path:path,capacityBytes:values.volumeTotalCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil },availableBytes:values.volumeAvailableCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil },isInternal:values.volumeIsInternal)
    }
}
