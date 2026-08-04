#include "renderer.h"
#include <cstdio>
#include <cmath>
#include <OpenGL/gl3.h>

static const char *vertex_shader_src = R"(
#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
uniform mat4 uMVP;
uniform mat4 uModel;
out vec3 vNormal;
out vec3 vWorldPos;
void main() {
    vec4 wp = uModel * vec4(aPos, 1.0);
    vWorldPos = wp.xyz;
    vNormal = mat3(uModel) * aNormal;
    gl_Position = uMVP * wp;
}
)";

static const char *fragment_shader_src = R"(
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
)";

static unsigned int compile_shader(const char *src, unsigned int type) {
    unsigned int s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    int ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "Shader error: %s\n", log);
    }
    return s;
}

bool MeshRenderer::upload(const float *positions, const float *normals,
                           const unsigned int *indices, int pos_count, int idx_count) {
    if (!vao) {
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo_v);
        glGenBuffers(1, &vbo_n);
        glGenBuffers(1, &ebo);

        // Shader
        unsigned int vs = compile_shader(vertex_shader_src, GL_VERTEX_SHADER);
        unsigned int fs = compile_shader(fragment_shader_src, GL_FRAGMENT_SHADER);
        shader = glCreateProgram();
        glAttachShader(shader, vs);
        glAttachShader(shader, fs);
        glLinkProgram(shader);
        glDeleteShader(vs);
        glDeleteShader(fs);
    }

    glBindVertexArray(vao);

    glBindBuffer(GL_ARRAY_BUFFER, vbo_v);
    glBufferData(GL_ARRAY_BUFFER, pos_count * sizeof(float), positions, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, 0);
    glEnableVertexAttribArray(0);

    glBindBuffer(GL_ARRAY_BUFFER, vbo_n);
    glBufferData(GL_ARRAY_BUFFER, pos_count * sizeof(float), normals, GL_STATIC_DRAW);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, 0);
    glEnableVertexAttribArray(1);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_count * sizeof(unsigned int), indices, GL_STATIC_DRAW);
    index_count = idx_count;

    glBindVertexArray(0);
    return true;
}

static void mat4_mult(float *r, const float *a, const float *b) {
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            r[i*4+j] = 0;
            for (int k = 0; k < 4; k++)
                r[i*4+j] += a[i*4+k] * b[k*4+j];
        }
}

static void perspective(float *m, float fov, float aspect, float near, float far) {
    float f = 1.0f / tanf(fov * 0.5f);
    for (int i = 0; i < 16; i++) m[i] = 0;
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (far + near) / (near - far);
    m[11] = -1;
    m[14] = (2 * far * near) / (near - far);
}

static void rotation_xy(float *m, float rx, float ry) {
    float cx = cosf(rx), sx = sinf(rx);
    float cy = cosf(ry), sy = sinf(ry);
    // R = Rx * Ry
    float rx_m[16] = {1,0,0,0, 0,cx,-sx,0, 0,sx,cx,0, 0,0,0,1};
    float ry_m[16] = {cy,0,sy,0, 0,1,0,0, -sy,0,cy,0, 0,0,0,1};
    mat4_mult(m, rx_m, ry_m);
}

static void translate_m(float *m, float x, float y, float z) {
    for (int i = 0; i < 16; i++) m[i] = 0;
    m[0]=1; m[5]=1; m[10]=1; m[15]=1;
    m[12]=x; m[13]=y; m[14]=z;
}

void MeshRenderer::render(int width, int height) {
    if (!vao || index_count == 0) return;

    glBindVertexArray(vao);
    glUseProgram(shader);

    float aspect = (float)width / (float)height;
    float proj[16], model[16], view[16], mvp[16], tmp[16];
    perspective(proj, 0.8f, aspect, 0.1f, 100.0f);
    rotation_xy(model, rotation_x, rotation_y);
    translate_m(view, pan_x, pan_y, -zoom);

    mat4_mult(tmp, view, model);
    mat4_mult(mvp, proj, tmp);

    glUniformMatrix4fv(glGetUniformLocation(shader, "uMVP"), 1, GL_FALSE, mvp);
    glUniformMatrix4fv(glGetUniformLocation(shader, "uModel"), 1, GL_FALSE, model);
    glUniform3f(glGetUniformLocation(shader, "uLightDir"), 0.5f, 0.8f, 0.6f);
    glUniform3f(glGetUniformLocation(shader, "uColor"), 0.65f, 0.72f, 0.85f);

    // Solid
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glDrawElements(GL_TRIANGLES, index_count, GL_UNSIGNED_INT, 0);

    // Wireframe
    glEnable(GL_POLYGON_OFFSET_LINE);
    glPolygonOffset(-1, -1);
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glUniform3f(glGetUniformLocation(shader, "uColor"), 0.2f, 0.2f, 0.25f);
    glLineWidth(1.0f);
    glDrawElements(GL_TRIANGLES, index_count, GL_UNSIGNED_INT, 0);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glDisable(GL_POLYGON_OFFSET_LINE);

    glBindVertexArray(0);
}

void MeshRenderer::reset_camera() {
    rotation_x = 0.3f; rotation_y = 0.0f;
    zoom = 3.0f; pan_x = pan_y = 0;
}

void MeshRenderer::mouse_drag(float dx, float dy, bool pan) {
    if (pan) {
        pan_x += dx * 0.005f;
        pan_y -= dy * 0.005f;
    } else {
        rotation_y += dx * 0.01f;
        rotation_x += dy * 0.01f;
    }
}

void MeshRenderer::mouse_scroll(float dy) {
    zoom *= 1.0f - dy * 0.1f;
    if (zoom < 0.1f) zoom = 0.1f;
    if (zoom > 50.0f) zoom = 50.0f;
}
