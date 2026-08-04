#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include <GLFW/glfw3.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <mutex>
#include <string>
#include <atomic>

#include "common.h"
#include "adjacency.h"
#include "bvh.h"
#include "dedge.h"
#include "extract.h"
#include "field.h"
#include "hierarchy.h"
#include "meshio.h"
#include "meshstats.h"
#include "normal.h"
#include "subdivide.h"
#include "nativefiledialog.h"
#include "renderer.h"

#include <map>
#include <set>
#include <memory>

// ===== App State =====
static struct App {
    bool running = true;
    int window_w = 1400, window_h = 900;
    MeshRenderer renderer;

    // Engine state
    std::unique_ptr<MultiResolutionHierarchy> mRes;
    bool mesh_loaded = false;
    bool orientation_computed = false;
    bool position_computed = false;
    bool mesh_extracted = false;

    int rosy = 4, posy = 4;
    bool extrinsic = true;
    float target_scale = -1;
    float crease_angle = -1;
    int target_faces = -1;

    // Extracted mesh
    MatrixXf O_extracted, Nf_extracted, N_extracted;
    MatrixXu F_extracted;
    std::vector<std::vector<TaggedLink>> adj_extracted;

    // Async processing
    std::thread worker;
    std::mutex work_mutex;
    std::atomic<bool> working{false};
    std::atomic<float> work_progress{0};
    char work_status[128] = "";
    std::string last_error;

    // UI state
    char status_msg[256] = "Ready. Open a mesh to begin.";
    float progress_bar = 0;
    bool show_progress = false;

    // Saved positions/normals/indices for renderer
    std::vector<float> render_positions;
    std::vector<float> render_normals;
    std::vector<unsigned int> render_indices;

    void update_render_data() {
        if (!mRes || !mesh_loaded) return;
        const MatrixXf &V = mRes->V(0);
        const MatrixXf &N = mRes->N(0);
        const MatrixXu &F = mRes->F();

        int nv = (int)V.cols();
        int nf = (int)F.cols();

        // Copy vertex data (column-major -> interleaved)
        render_positions.resize(nv * 3);
        render_normals.resize(nv * 3);
        for (int i = 0; i < nv; i++) {
            for (int k = 0; k < 3; k++) {
                render_positions[i*3+k] = V(k, i);
                render_normals[i*3+k] = N(k, i);
            }
        }

        render_indices.resize(nf * 3);
        for (int i = 0; i < nf; i++) {
            render_indices[i*3+0] = F(0, i);
            render_indices[i*3+1] = F(1, i);
            render_indices[i*3+2] = F(2, i);
        }

        renderer.upload(render_positions.data(), render_normals.data(),
                        render_indices.data(), nv * 3, nf * 3);
    }
} app;

// ===== Algorithm wrappers =====

static void do_load_mesh(const char *path) {
    std::lock_guard<std::mutex> lock(app.work_mutex);

    app.mesh_loaded = false;
    app.orientation_computed = false;
    app.position_computed = false;
    app.mesh_extracted = false;
    if (app.mRes) app.mRes->free();
    app.mRes = std::make_unique<MultiResolutionHierarchy>();
    app.render_indices.clear();

    app.work_progress = 0;
    snprintf(app.work_status, sizeof(app.work_status), "Loading mesh...");

    auto cb = [](const std::string &stage, Float p) {
        app.work_progress = p;
        snprintf(app.work_status, sizeof(app.work_status), "%s", stage.c_str());
    };

    MatrixXu F;
    MatrixXf V, N;
    try {
        load_mesh_or_pointcloud(std::string(path), F, V, N, cb);
    } catch (const std::exception &e) {
        app.last_error = e.what();
        app.working = false;
        return;
    }
    if (F.cols() == 0 && V.cols() == 0) {
        app.last_error = "Empty mesh";
        app.working = false;
        return;
    }

    MeshStats stats = compute_mesh_stats(F, V, false, cb);

    // Subdivide if too coarse
    if (F.size() > 0) {
        Float maxLen = stats.mMaximumEdgeLength * 2;
        for (int it = 0; it < 5; ++it) {
            VectorXu V2E, E2E; VectorXb boundary, nonManifold;
            build_dedge(F, V, V2E, E2E, boundary, nonManifold, cb);
            if (stats.mMaximumEdgeLength > maxLen) {
                subdivide(F, V, V2E, E2E, boundary, nonManifold, maxLen, false, cb);
                stats = compute_mesh_stats(F, V, false, cb);
                maxLen = stats.mMaximumEdgeLength * 2;
            } else break;
        }
    }

    app.mRes->free();
    app.mRes->setF(std::move(MatrixXu(F)));
    app.mRes->setV(std::move(MatrixXf(V)));

    if (F.size() > 0) {
        VectorXu V2E, E2E; VectorXb boundary, nonManifold;
        build_dedge(F, V, V2E, E2E, boundary, nonManifold, cb);
        AdjacencyMatrix adj = generate_adjacency_matrix_uniform(F, V2E, E2E, nonManifold, cb);

        MatrixXf Ns(3, V.cols());
        if (app.crease_angle >= 0) {
            std::map<uint32_t,uint32_t> creaseMap;
            generate_crease_normals(F, V, V2E, E2E, boundary, nonManifold,
                                     app.crease_angle, Ns, creaseMap, cb);
        } else {
            generate_smooth_normals(F, V, V2E, E2E, nonManifold, Ns, cb);
        }

        VectorXf A(V.cols());
        compute_dual_vertex_areas(F, V, V2E, E2E, nonManifold, A, cb);

        app.mRes->setAdj(std::move(AdjacencyMatrix(adj)));
        app.mRes->setN(std::move(MatrixXf(Ns)));
        app.mRes->setA(std::move(VectorXf(A)));
    }

    if (app.target_scale > 0) app.mRes->setScale(app.target_scale);
    else if (app.target_faces > 0)
        app.mRes->setScale(std::sqrt((Float)app.mRes->size() / (Float)app.target_faces));

    app.mRes->build(false, cb);
    app.mRes->resetSolution();
    app.mesh_loaded = true;

    app.update_render_data();
    snprintf(app.status_msg, sizeof(app.status_msg),
             "Loaded: %d vertices, %d faces",
             (int)app.mRes->V(0).cols(), (int)app.mRes->F().cols());
    app.working = false;
}

static void do_solve_orientations() {
    std::lock_guard<std::mutex> lock(app.work_mutex);
    if (!app.mesh_loaded) { app.working = false; return; }

    app.work_progress = 0;
    try {
        int nL = app.mRes->levels();
        for (int l = nL-1; l >= 0; --l) {
            app.work_progress = 1.f - (float)l/(float)nL;
            snprintf(app.work_status, sizeof(app.work_status), "Orientations level %d/%d", l+1, nL);
            for (int it = 0; it < 6; ++it)
                optimize_orientations(*app.mRes, l, app.extrinsic, app.rosy, [](uint32_t){});
            // Propagate
            for (int i = l-1; i >= 0; --i) {
                const MatrixXf &s = app.mRes->Q(i+1);
                const MatrixXu &tu = app.mRes->toUpper(i);
                MatrixXf &d = app.mRes->Q(i);
                const MatrixXf &N = app.mRes->N(i);
                for (uint32_t j = 0; j < (uint32_t)s.cols(); ++j)
                    for (int k = 0; k < 2; ++k) {
                        uint32_t t = tu(k,j);
                        if (t == (uint32_t)-1) continue;
                        Vector3f q = s.col(j), n = N.col(t);
                        d.col(t) = q - n*n.dot(q);
                    }
            }
        }
        app.orientation_computed = true;
        snprintf(app.status_msg, sizeof(app.status_msg), "Orientation field solved.");
    } catch (const std::exception &e) {
        app.last_error = e.what();
        snprintf(app.status_msg, sizeof(app.status_msg), "Error: %s", e.what());
    }
    app.working = false;
}

static void do_solve_positions() {
    std::lock_guard<std::mutex> lock(app.work_mutex);
    if (!app.orientation_computed) { app.working = false; return; }

    app.work_progress = 0;
    try {
        int nL = app.mRes->levels();
        for (int l = nL-1; l >= 0; --l) {
            app.work_progress = 1.f - (float)l/(float)nL;
            snprintf(app.work_status, sizeof(app.work_status), "Positions level %d/%d", l+1, nL);
            for (int it = 0; it < 6; ++it)
                optimize_positions(*app.mRes, l, app.extrinsic, app.posy, [](uint32_t){});
            for (int i = l-1; i >= 0; --i) {
                const MatrixXf &s = app.mRes->O(i+1);
                MatrixXf &d = app.mRes->O(i);
                const MatrixXf &N = app.mRes->N(i), &V = app.mRes->V(i);
                const MatrixXu &tu = app.mRes->toUpper(i);
                for (uint32_t j = 0; j < (uint32_t)s.cols(); ++j)
                    for (int k = 0; k < 2; ++k) {
                        uint32_t t = tu(k,j);
                        if (t == (uint32_t)-1) continue;
                        Vector3f o = s.col(j), n = N.col(t), v = V.col(t);
                        o -= n*n.dot(o-v);
                        d.col(t) = o;
                    }
            }
        }
        app.position_computed = true;
        snprintf(app.status_msg, sizeof(app.status_msg), "Position field solved.");
    } catch (const std::exception &e) {
        app.last_error = e.what();
        snprintf(app.status_msg, sizeof(app.status_msg), "Error: %s", e.what());
    }
    app.working = false;
}

static void do_extract() {
    std::lock_guard<std::mutex> lock(app.work_mutex);
    if (!app.position_computed) { app.working = false; return; }

    app.work_progress = 0;
    try {
        app.work_progress = 0.25f;
        snprintf(app.work_status, sizeof(app.work_status), "Extracting graph...");
        app.adj_extracted.clear();
        app.O_extracted.resize(3, app.mRes->size());
        app.N_extracted.resize(3, app.mRes->size());
        std::set<uint32_t> ci, co;
        extract_graph(*app.mRes, app.extrinsic, app.rosy, app.posy, app.adj_extracted,
                      app.O_extracted, app.N_extracted, ci, co, true);

        app.work_progress = 0.6f;
        snprintf(app.work_status, sizeof(app.work_status), "Extracting faces...");
        extract_faces(app.adj_extracted, app.O_extracted, app.N_extracted,
                      app.Nf_extracted, app.F_extracted, app.posy,
                      app.mRes->scale(), co, true, true);

        app.mesh_extracted = true;
        int nf = (int)app.F_extracted.cols();
        snprintf(app.status_msg, sizeof(app.status_msg),
                 "Extracted: %d faces. Ready to export.", nf);
    } catch (const std::exception &e) {
        app.last_error = e.what();
        snprintf(app.status_msg, sizeof(app.status_msg), "Error: %s", e.what());
    }
    app.working = false;
}

static void do_export(const char *path) {
    std::lock_guard<std::mutex> lock(app.work_mutex);
    if (!app.mesh_extracted) { app.working = false; return; }
    try {
        write_mesh(std::string(path), app.F_extracted, app.O_extracted, MatrixXf(), app.Nf_extracted);
        snprintf(app.status_msg, sizeof(app.status_msg), "Exported to: %s", path);
    } catch (const std::exception &e) {
        app.last_error = e.what();
        snprintf(app.status_msg, sizeof(app.status_msg), "Export error: %s", e.what());
    }
    app.working = false;
}

#include <functional>

int nprocs = -1; // required by field.cpp Optimizer

static void launch_work(std::function<void()> fn) {
    if (app.working) return;
    app.working = true;
    app.work_progress = 0;
    app.show_progress = true;
    if (app.worker.joinable()) app.worker.join();
    app.worker = std::thread(fn);
}

// ===== Main =====

static void glfw_error_callback(int error, const char *desc) {
    fprintf(stderr, "GLFW error %d: %s\n", error, desc);
}

int main(int, char**) {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit()) return -1;

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    glfwWindowHint(GLFW_SAMPLES, 4);

    GLFWwindow *window = glfwCreateWindow(app.window_w, app.window_h,
                                           "Instant Meshes", NULL, NULL);
    if (!window) { glfwTerminate(); return -1; }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    // ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigWindowsMoveFromTitleBarOnly = true;

    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 330");

    // Load font
    io.Fonts->AddFontDefault();

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_MULTISAMPLE);

    while (app.running && !glfwWindowShouldClose(window)) {
        glfwPollEvents();

        // Check if worker finished
        if (!app.working.load() && app.show_progress) {
            app.progress_bar = 0;
            app.show_progress = false;
        }

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        // --- 3D Viewport ---
        {
            ImGui::SetNextWindowPos(ImVec2(0, 0));
            ImGui::SetNextWindowSize(ImVec2((float)(app.window_w * 0.7f), (float)app.window_h));
            ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
            ImGui::Begin("##3dview", nullptr,
                         ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
                         ImGuiWindowFlags_NoScrollWithMouse);

            ImVec2 vp = ImGui::GetContentRegionAvail();
            int vp_w = (int)vp.x, vp_h = (int)vp.y;

            if (vp_w > 0 && vp_h > 0) {
                // Mouse interaction
                if (ImGui::IsWindowHovered()) {
                    ImGuiIO &io2 = ImGui::GetIO();
                    if (ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
                        app.renderer.mouse_drag(io2.MouseDelta.x, io2.MouseDelta.y,
                                                 io2.KeyShift);
                    }
                    app.renderer.mouse_scroll(io2.MouseWheel);
                }

                app.renderer.render(vp_w, vp_h);

                // Show render as image
                ImGui::Image((ImTextureID)(intptr_t)0, vp, ImVec2(0,1), ImVec2(1,0));
            }
            ImGui::End();
            ImGui::PopStyleVar();
        }

        // --- Sidebar Panel ---
        {
            ImVec2 panel_pos((float)(app.window_w * 0.7f), 0);
            ImVec2 panel_size((float)(app.window_w * 0.3f), (float)app.window_h);
            ImGui::SetNextWindowPos(panel_pos);
            ImGui::SetNextWindowSize(panel_size);
            ImGui::Begin("##panel", nullptr,
                         ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove);

            ImGui::Text("Instant Meshes");
            ImGui::Separator();

            // Load
            if (ImGui::Button("Open Mesh...", ImVec2(-1, 30))) {
                const char *exts[] = {"obj", "ply", "aln", NULL};
                char *path = native_open_dialog(exts);
                if (path) {
                    launch_work([path]() { do_load_mesh(path); free(path); });
                }
            }
            ImGui::SameLine();
            ImGui::TextDisabled("(.obj/.ply)");

            // Settings
            if (ImGui::CollapsingHeader("Settings")) {
                ImGui::SliderInt("RoSy", &app.rosy, 2, 6);
                if (app.rosy != 2 && app.rosy != 4) app.rosy = 4;
                ImGui::SliderInt("PoSy", &app.posy, 3, 4);

                ImGui::Checkbox("Extrinsic", &app.extrinsic);
                ImGui::InputFloat("Crease Angle", &app.crease_angle, 1, 10, "%.0f deg");
                ImGui::InputFloat("Scale", &app.target_scale, 0.1f, 1, "%.1f");
                if (ImGui::Button("Reset Camera"))
                    app.renderer.reset_camera();
            }

            ImGui::Separator();

            // Solve orientation
            if (ImGui::Button("1. Solve Orientation Field", ImVec2(-1, 35))) {
                launch_work(do_solve_orientations);
            }
            if (app.orientation_computed) {
                ImGui::SameLine();
                ImGui::TextColored(ImVec4(0,1,0,1), "Done");
            }

            // Solve position
            ImGui::BeginDisabled(!app.orientation_computed);
            if (ImGui::Button("2. Solve Position Field", ImVec2(-1, 35))) {
                launch_work(do_solve_positions);
            }
            if (app.position_computed) {
                ImGui::SameLine();
                ImGui::TextColored(ImVec4(0,1,0,1), "Done");
            }
            ImGui::EndDisabled();

            // Extract
            ImGui::BeginDisabled(!app.position_computed);
            if (ImGui::Button("3. Extract Mesh", ImVec2(-1, 35))) {
                launch_work(do_extract);
            }
            if (app.mesh_extracted) {
                ImGui::SameLine();
                ImGui::TextColored(ImVec4(0,1,0,1), "Done");
            }
            ImGui::EndDisabled();

            ImGui::Separator();

            // Export
            ImGui::BeginDisabled(!app.mesh_extracted);
            if (ImGui::Button("Export Mesh...", ImVec2(-1, 35))) {
                char *path = native_save_dialog("remeshed.obj");
                if (path) {
                    launch_work([path]() { do_export(path); free(path); });
                }
            }
            ImGui::EndDisabled();

            ImGui::Separator();

            // Status
            if (app.show_progress) {
                ImGui::ProgressBar(app.work_progress, ImVec2(-1, 20));
                ImGui::Text("%s", app.work_status);
            } else {
                ImGui::TextWrapped("%s", app.status_msg);
            }

            if (!app.last_error.empty()) {
                ImGui::TextColored(ImVec4(1,0.3f,0.3f,1), "Error: %s", app.last_error.c_str());
                if (ImGui::Button("Dismiss")) app.last_error.clear();
            }

            ImGui::End();
        }

        // --- Render ---
        ImGui::Render();
        int display_w, display_h;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(0.12f, 0.12f, 0.14f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        glfwSwapBuffers(window);

        // Update window size
        glfwGetWindowSize(window, &app.window_w, &app.window_h);
    }

    // Cleanup
    app.working = false;
    if (app.worker.joinable()) app.worker.join();

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
