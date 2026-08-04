import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var viewModel: MeshViewModel

    var body: some View {
        HSplitView {
            GLMeshView()
                .environmentObject(viewModel)
                .frame(minWidth: 500)

            VStack(alignment: .leading, spacing: 12) {
                // ---- Load Section ----
                GroupBox("Input") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(action: openFile) {
                                Label(viewModel.hasMesh ? "Mesh Loaded" : "Open Mesh...",
                                      systemImage: viewModel.hasMesh ? "checkmark.circle.fill" : "folder")
                            }
                            .disabled(viewModel.isProcessing)

                            if viewModel.hasMesh {
                                Text("\(viewModel.vertexCount) V / \(viewModel.faceCount) F")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let info = viewModel.meshInfo {
                            Text(String(format: "BBox: [%.1f, %.1f, %.1f] - [%.1f, %.1f, %.1f]",
                                        info.minX, info.minY, info.minZ,
                                        info.maxX, info.maxY, info.maxZ))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        TextField("Crease Angle (degrees, -1 = auto)", value: $viewModel.creaseAngle, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .disabled(viewModel.isProcessing)

                        Picker("Symmetry", selection: $viewModel.rosy) {
                            Text("2-RoSy").tag(2)
                            Text("4-RoSy (Quad)").tag(4)
                            Text("6-RoSy (Hex)").tag(6)
                        }
                        .disabled(viewModel.isProcessing)

                        Picker("Mode", selection: $viewModel.useExtrinsic) {
                            Text("Extrinsic").tag(true)
                            Text("Intrinsic").tag(false)
                        }
                        .disabled(viewModel.isProcessing)

                        HStack {
                            Picker("Density", selection: $viewModel.densityMode) {
                                Text("Auto").tag(0)
                                Text("Scale").tag(1)
                                Text("Face Count").tag(2)
                            }
                            .disabled(viewModel.isProcessing)

                            if viewModel.densityMode == 1 {
                                TextField("Scale", value: $viewModel.targetScale, format: .number)
                            } else if viewModel.densityMode == 2 {
                                TextField("Faces", value: $viewModel.targetFaceCount, format: .number)
                            }
                        }
                    }
                    .padding(4)
                }

                // ---- Solve Section ----
                GroupBox("Compute") {
                    VStack(spacing: 8) {
                        Button(action: { viewModel.computeOrientationField() }) {
                            Label("Solve Orientation Field", systemImage: viewModel.hasOrientationField ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        }
                        .disabled(!viewModel.hasMesh || viewModel.isProcessing)
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.hasOrientationField ? .green : .blue)

                        Button(action: { viewModel.computePositionField() }) {
                            Label("Solve Position Field", systemImage: viewModel.hasPositionField ? "checkmark.circle.fill" : "arrowshape.turn.up.right")
                        }
                        .disabled(!viewModel.hasOrientationField || viewModel.isProcessing)
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.hasPositionField ? .green : .blue)
                    }
                    .padding(4)
                }

                // ---- Export Section ----
                GroupBox("Export") {
                    VStack(spacing: 8) {
                        Button(action: { viewModel.extractAndExport() }) {
                            Label("Extract & Export Mesh...", systemImage: viewModel.hasExtractedMesh ? "checkmark.circle.fill" : "square.and.arrow.up")
                        }
                        .disabled(!viewModel.hasPositionField || viewModel.isProcessing)
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.hasExtractedMesh ? .green : .orange)

                        if viewModel.hasExtractedMesh {
                            Text("Extracted: \(viewModel.extractedFaceCount) faces")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(4)
                }

                // ---- Status ----
                if viewModel.isProcessing {
                    VStack(spacing: 6) {
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .frame(minWidth: 280, idealWidth: 300)
            .padding(8)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "obj") ?? .plainText,
            UTType(filenameExtension: "ply") ?? .plainText,
            UTType(filenameExtension: "aln") ?? .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadMesh(url: url)
        }
    }
}
