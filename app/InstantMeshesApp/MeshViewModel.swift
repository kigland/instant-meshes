import Foundation
import SwiftUI

@MainActor
class MeshViewModel: ObservableObject {
    @Published var hasMesh = false
    @Published var hasOrientationField = false
    @Published var hasPositionField = false
    @Published var hasExtractedMesh = false
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    @Published var vertexCount: UInt32 = 0
    @Published var faceCount: UInt32 = 0
    @Published var extractedFaceCount: UInt32 = 0
    @Published var meshInfo: MeshInfoData? = nil

    @Published var creaseAngle: Float = -1
    @Published var rosy: Int = 4
    @Published var useExtrinsic: Bool = true
    @Published var densityMode: Int = 0
    @Published var targetScale: Float = -1
    @Published var targetFaceCount: Float = -1

    // GL data
    @Published var renderVertexPositions: Data?
    @Published var renderVertexNormals: Data?
    @Published var renderFaceIndices: Data?
    @Published var vertexCountGL: Int = 0
    @Published var faceCountGL: Int = 0

    private var engine: OpaquePointer? = nil
    private let queue = DispatchQueue(label: "com.instantmeshes.engine", qos: .userInitiated)

    struct MeshInfoData {
        let vertexCount: UInt32
        let faceCount: UInt32
        let minX: Float; let minY: Float; let minZ: Float
        let maxX: Float; let maxY: Float; let maxZ: Float
    }

    init() {
        engine = mesh_engine_create()
    }

    deinit {
        if let e = engine {
            mesh_engine_destroy(e)
        }
    }

    func loadMesh(url: URL) {
        guard let e = engine else { return }
        isProcessing = true
        statusMessage = "Loading mesh..."
        progress = 0

        queue.async { [weak self] in
            guard let self = self else { return }

            let infoPtr = url.path.withCString { path in
                mesh_engine_load(e, path, self.creaseAngle, false) { stagePtr, pct in
                    let stage = stagePtr.map { String(cString: $0) } ?? ""
                    Task { @MainActor in
                        self?.statusMessage = stage
                        self?.progress = Double(pct)
                    }
                }
            }

            Task { @MainActor in
                guard let infoPtr = infoPtr else {
                    self.isProcessing = false
                    return
                }
                let info = infoPtr.pointee
                self.meshInfo = MeshInfoData(
                    vertexCount: info.vertexCount,
                    faceCount: info.faceCount,
                    minX: info.minX, minY: info.minY, minZ: info.minZ,
                    maxX: info.maxX, maxY: info.maxY, maxZ: info.maxZ
                )
                self.vertexCount = info.vertexCount
                self.faceCount = info.faceCount
                self.hasMesh = true
                self.hasOrientationField = false
                self.hasPositionField = false
                self.hasExtractedMesh = false
                infoPtr.deallocate()

                // Load render data
                self.refreshRenderData()
                self.isProcessing = false
                self.progress = 0
                self.statusMessage = ""
            }
        }
    }

    private func refreshRenderData() {
        guard let e = engine, hasMesh else { return }

        var posCount: Int32 = 0
        var normCount: Int32 = 0
        var faceCount32: Int32 = 0

        if let posPtr = mesh_engine_get_positions(e, &posCount),
           let normPtr = mesh_engine_get_normals(e, &normCount),
           let facePtr = mesh_engine_get_faces(e, &faceCount32),
           posCount > 0 {

            renderVertexPositions = Data(bytes: posPtr, count: Int(posCount) * MemoryLayout<Float>.size)
            renderVertexNormals = Data(bytes: normPtr, count: Int(normCount) * MemoryLayout<Float>.size)
            renderFaceIndices = Data(bytes: facePtr, count: Int(faceCount32) * MemoryLayout<UInt32>.size)
            vertexCountGL = Int(posCount) / 3
            faceCountGL = Int(faceCount32) / 3
        }
    }

    func computeOrientationField() {
        guard let e = engine, hasMesh else { return }
        isProcessing = true
        statusMessage = "Solving orientation field..."

        mesh_engine_set_rosy(e, Int32(rosy))
        mesh_engine_set_extrinsic(e, useExtrinsic)

        queue.async { [weak self] in
            guard let self = self else { return }
            _ = mesh_engine_compute_orientation(e) { stagePtr, pct in
                let stage = stagePtr.map { String(cString: $0) } ?? ""
                Task { @MainActor in
                    self?.statusMessage = stage
                    self?.progress = Double(pct)
                }
            }
            Task { @MainActor in
                self.hasOrientationField = true
                self.isProcessing = false
                self.progress = 0
                self.statusMessage = ""
            }
        }
    }

    func computePositionField() {
        guard let e = engine, hasOrientationField else { return }
        isProcessing = true
        statusMessage = "Solving position field..."

        mesh_engine_set_posy(e, 4)

        queue.async { [weak self] in
            guard let self = self else { return }
            _ = mesh_engine_compute_position(e) { stagePtr, pct in
                let stage = stagePtr.map { String(cString: $0) } ?? ""
                Task { @MainActor in
                    self?.statusMessage = stage
                }
            }
            Task { @MainActor in
                self.hasPositionField = true
                self.isProcessing = false
                self.progress = 0
                self.statusMessage = ""
            }
        }
    }

    func extractAndExport() {
        guard let e = engine, hasPositionField else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "obj") ?? .plainText,
            UTType(filenameExtension: "ply") ?? .plainText,
        ]
        panel.nameFieldStringValue = "remeshed.obj"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }

            self.isProcessing = true
            self.statusMessage = "Extracting..."

            self.queue.async {
                _ = mesh_engine_extract(e) { stagePtr, pct in
                    let stage = stagePtr.map { String(cString: $0) } ?? ""
                    Task { @MainActor in
                        self.statusMessage = stage
                        self.progress = Double(pct)
                    }
                }

                url.path.withCString { path in
                    _ = mesh_engine_export(e, path)
                }

                Task { @MainActor in
                    self.extractedFaceCount = mesh_engine_extracted_faces(e)
                    self.hasExtractedMesh = true
                    self.isProcessing = false
                    self.progress = 0
                    self.statusMessage = ""
                }
            }
        }
    }
}
