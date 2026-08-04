import AppKit
import OpenGL.GL3
import SwiftUI

// MARK: - SwiftUI Wrapper

struct GLMeshView: NSViewRepresentable {
    @EnvironmentObject var viewModel: MeshViewModel

    func makeNSView(context: Context) -> MeshRendererNSView {
        let view = MeshRendererNSView()
        return view
    }

    func updateNSView(_ nsView: MeshRendererNSView, context: Context) {
        nsView.updateData(
            positions: viewModel.renderVertexPositions,
            normals: viewModel.renderVertexNormals,
            faces: viewModel.renderFaceIndices,
            vertexCount: viewModel.vertexCountGL,
            faceCount: viewModel.faceCountGL
        )
    }
}

// MARK: - NSOpenGLView

class MeshRendererNSView: NSOpenGLView {
    private var shaderProgram: GLuint = 0
    private var vao: GLuint = 0
    private var vboPos: GLuint = 0
    private var vboNorm: GLuint = 0
    private var ebo: GLuint = 0

    private var indexCount: GLsizei = 0
    private var hasData = false

    // Camera
    private var rotationX: Float = 0.3
    private var rotationY: Float = 0.0
    private var zoom: Float = 3.0
    private var panX: Float = 0
    private var panY: Float = 0
    private var lastMouse: NSPoint = .zero

    // Trackpad rotation state
    private var trackballRotation: SIMD3<Float> = .zero

    override init(frame frameRect: NSRect, pixelFormat: NSOpenGLPixelFormat?) {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAMultisample),
            UInt32(NSOpenGLPFASampleBuffers), 1,
            UInt32(NSOpenGLPFASamples), 4,
            0
        ]
        let pf = NSOpenGLPixelFormat(attributes: attrs)
        super.init(frame: frameRect, pixelFormat: pf)
        setup()
    }

    required init?(coder: NSCoder) {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFADoubleBuffer),
            0
        ]
        let pf = NSOpenGLPixelFormat(attributes: attrs)
        super.init(coder: coder)
        self.pixelFormat = pf
        setup()
    }

    // MARK: - Setup

    private func setup() {
        wantsBestResolutionOpenGLSurface = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: nil)

        // Trackpad gesture support
        let panRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panRecognizer)

        let magnificationRecognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        addGestureRecognizer(magnificationRecognizer)
    }

    @objc private func windowDidBecomeKey() {
        needsDisplay = true
    }

    // MARK: - OpenGL Init

    override func prepareOpenGL() {
        super.prepareOpenGL()

        guard let ctx = openGLContext else { return }
        ctx.makeCurrentContext()

        glEnable(GLenum(GL_DEPTH_TEST))
        glEnable(GLenum(GL_MULTISAMPLE))
        glClearColor(0.15, 0.15, 0.17, 1.0)

        shaderProgram = createShaderProgram()
    }

    override func reshape() {
        super.reshape()
        guard let ctx = openGLContext else { return }
        ctx.update()
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = openGLContext else { return }
        ctx.makeCurrentContext()

        glClear(GLenum(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))

        let aspect = Float(bounds.width / max(bounds.height, 1))

        guard hasData, shaderProgram != 0 else {
            // Draw placeholder when no data
            glClearColor(0.12, 0.12, 0.14, 1.0)
            ctx.flushBuffer()
            return
        }

        glClearColor(0.15, 0.15, 0.17, 1.0)
        glUseProgram(shaderProgram)

        // Model matrix
        let modelLoc = glGetUniformLocation(shaderProgram, "uModel")
        var model: [Float] = [
            cos(rotationY), 0, sin(rotationY), 0,
            0, 1, 0, 0,
            -sin(rotationY), 0, cos(rotationY), 0,
            0, 0, 0, 1
        ]
        // Combine rotationX
        let rx: [Float] = [
            1, 0, 0, 0,
            0, cos(rotationX), -sin(rotationX), 0,
            0, sin(rotationX), cos(rotationX), 0,
            0, 0, 0, 1
        ]
        model = mat4Multiply(rx, model)
        glUniformMatrix4fv(modelLoc, 1, GLboolean(GL_FALSE), &model)

        // View matrix
        let viewLoc = glGetUniformLocation(shaderProgram, "uView")
        var viewMatrix: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            panX, panY, -zoom, 1
        ]
        glUniformMatrix4fv(viewLoc, 1, GLboolean(GL_FALSE), &viewMatrix)

        // Projection matrix
        let projLoc = glGetUniformLocation(shaderProgram, "uProjection")
        let fov: Float = 0.8
        let near: Float = 0.1
        let far: Float = 100.0
        let f = 1.0 / tan(fov / 2.0)
        var projMatrix: [Float] = [
            f / aspect, 0, 0, 0,
            0, f, 0, 0,
            0, 0, (far + near) / (near - far), -1,
            0, 0, (2 * far * near) / (near - far), 0
        ]
        glUniformMatrix4fv(projLoc, 1, GLboolean(GL_FALSE), &projMatrix)

        // Light
        let lightLoc = glGetUniformLocation(shaderProgram, "uLightDir")
        glUniform3f(lightLoc, 0.5, 0.8, 0.6)

        // Wireframe overlay (second pass with polygon offset)
        glBindVertexArray(vao)

        // Solid pass
        glPolygonMode(GLenum(GL_FRONT_AND_BACK), GLenum(GL_FILL))
        let colorLoc = glGetUniformLocation(shaderProgram, "uColor")
        glUniform3f(colorLoc, 0.65, 0.72, 0.85)
        glDrawElements(GLenum(GL_TRIANGLES), indexCount, GLenum(GL_UNSIGNED_INT), nil)

        // Wireframe pass
        glEnable(GLenum(GL_POLYGON_OFFSET_LINE))
        glPolygonOffset(-1, -1)
        glPolygonMode(GLenum(GL_FRONT_AND_BACK), GLenum(GL_LINE))
        glUniform3f(colorLoc, 0.2, 0.2, 0.25)
        glLineWidth(1.0)
        glDrawElements(GLenum(GL_TRIANGLES), indexCount, GLenum(GL_UNSIGNED_INT), nil)
        glPolygonMode(GLenum(GL_FRONT_AND_BACK), GLenum(GL_FILL))
        glDisable(GLenum(GL_POLYGON_OFFSET_LINE))

        glBindVertexArray(0)
        glUseProgram(0)

        ctx.flushBuffer()
    }

    // MARK: - Data Update

    func updateData(positions: Data?, normals: Data?, faces: Data?, vertexCount: Int, faceCount: Int) {
        guard let pos = positions, let norms = normals, let faceIdx = faces,
              !pos.isEmpty, !norms.isEmpty, !faceIdx.isEmpty else {
            return
        }

        guard let ctx = openGLContext else { return }
        ctx.makeCurrentContext()

        if vao == 0 {
            glGenVertexArrays(1, &vao)
        }
        glBindVertexArray(vao)

        // Positions
        if vboPos == 0 { glGenBuffers(1, &vboPos) }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboPos)
        pos.withUnsafeBytes { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), ptr.count, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, nil)

        // Normals
        if vboNorm == 0 { glGenBuffers(1, &vboNorm) }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboNorm)
        norms.withUnsafeBytes { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), ptr.count, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, nil)

        // Indices
        if ebo == 0 { glGenBuffers(1, &ebo) }
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), ebo)
        faceIdx.withUnsafeBytes { ptr in
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), ptr.count, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        indexCount = GLsizei(faceIdx.count / MemoryLayout<UInt32>.size)

        glBindVertexArray(0)

        hasData = true
        needsDisplay = true
    }

    // MARK: - Shaders

    private func createShaderProgram() -> GLuint {
        let vertexShader = """
        #version 330 core
        layout(location = 0) in vec3 aPos;
        layout(location = 1) in vec3 aNormal;
        uniform mat4 uModel;
        uniform mat4 uView;
        uniform mat4 uProjection;
        out vec3 vNormal;
        out vec3 vWorldPos;
        void main() {
            vec4 worldPos = uModel * vec4(aPos, 1.0);
            vWorldPos = worldPos.xyz;
            vNormal = mat3(uModel) * aNormal;
            gl_Position = uProjection * uView * worldPos;
        }
        """

        let fragmentShader = """
        #version 330 core
        in vec3 vNormal;
        in vec3 vWorldPos;
        uniform vec3 uLightDir;
        uniform vec3 uColor;
        out vec4 fragColor;
        void main() {
            vec3 N = normalize(vNormal);
            vec3 L = normalize(uLightDir);
            float ambient = 0.25;
            float diffuse = max(dot(N, L), 0.0) * 0.75;
            vec3 lit = uColor * (ambient + diffuse);
            fragColor = vec4(lit, 1.0);
        }
        """

        return compileShader(vertex: vertexShader, fragment: fragmentShader)
    }

    private func compileShader(vertex vSrc: String, fragment fSrc: String) -> GLuint {
        let vs = compileSingleShader(source: vSrc, type: GLenum(GL_VERTEX_SHADER))
        let fs = compileSingleShader(source: fSrc, type: GLenum(GL_FRAGMENT_SHADER))
        let prog = glCreateProgram()
        glAttachShader(prog, vs)
        glAttachShader(prog, fs)
        glLinkProgram(prog)

        var success: GLint = 0
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &success)
        if success == GL_FALSE {
            var logLen: GLint = 0
            glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(logLen))
            glGetProgramInfoLog(prog, logLen, nil, &log)
            print("Shader link error: \(String(cString: log))")
        }

        glDeleteShader(vs)
        glDeleteShader(fs)
        return prog
    }

    private func compileSingleShader(source: String, type: GLenum) -> GLuint {
        let shader = glCreateShader(type)
        var src = (source as NSString).utf8String
        glShaderSource(shader, 1, &src, nil)
        glCompileShader(shader)

        var success: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &success)
        if success == GL_FALSE {
            var logLen: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(logLen))
            glGetShaderInfoLog(shader, logLen, nil, &log)
            print("Shader compile error: \(String(cString: log))")
        }
        return shader
    }

    // MARK: - Mouse / Trackpad

    override func mouseDown(with event: NSEvent) {
        lastMouse = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = Float(p.x - lastMouse.x)
        let dy = Float(p.y - lastMouse.y)

        if event.modifierFlags.contains(.shift) {
            panX += dx * 0.005
            panY -= dy * 0.005
        } else {
            rotationY += dx * 0.01
            rotationX += dy * 0.01
        }

        lastMouse = p
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        zoom *= 1.0 - Float(event.deltaY) * 0.01
        zoom = max(0.1, min(zoom, 50.0))
        needsDisplay = true
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        rotationY += Float(translation.x) * 0.01
        rotationX += Float(translation.y) * 0.01
        gesture.setTranslation(.zero, in: self)
        needsDisplay = true
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        zoom *= 1.0 - Float(gesture.magnification)
        zoom = max(0.1, min(zoom, 50.0))
        gesture.magnification = 0
        needsDisplay = true
    }

    // MARK: - Helpers

    private func mat4Multiply(_ a: [Float], _ b: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: 16)
        for i in 0..<4 {
            for j in 0..<4 {
                for k in 0..<4 {
                    result[i * 4 + j] += a[i * 4 + k] * b[k * 4 + j]
                }
            }
        }
        return result
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { true }
}
