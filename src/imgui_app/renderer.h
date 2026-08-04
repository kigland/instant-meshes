#ifndef MESH_RENDERER_H
#define MESH_RENDERER_H

#include <vector>
#include <Eigen/Core>

struct MeshRenderer {
    unsigned int vao = 0, vbo_v = 0, vbo_n = 0, ebo = 0;
    unsigned int shader = 0;
    int index_count = 0;

    float rotation_x = 0.3f, rotation_y = 0.0f;
    float zoom = 3.0f;
    float pan_x = 0, pan_y = 0;

    bool upload(const float *positions, const float *normals,
                const unsigned int *indices, int pos_count, int idx_count);
    void render(int width, int height);
    void reset_camera();
    void mouse_drag(float dx, float dy, bool pan);
    void mouse_scroll(float dy);
};

#endif
