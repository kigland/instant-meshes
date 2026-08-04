/*
 * instantmeshes-cli — command line interface for Instant Meshes
 * Supports OBJ, PLY, GLB, glTF input formats.
 */
#include "common.h"
#include "meshio.h"
#include "dedge.h"
#include "subdivide.h"
#include "meshstats.h"
#include "hierarchy.h"
#include "field.h"
#include "normal.h"
#include "extract.h"
#include "bvh.h"
#include <cstring>
#include <map>
#include <set>

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

int nprocs = -1;

static void print_usage(const char *prog) {
    printf("Usage: %s [options] <input> <output>\n\n", prog);
    printf("Input formats: .obj, .ply, .glb, .gltf\n");
    printf("Output formats: .obj, .ply\n\n");
    printf("Options:\n");
    printf("  -r, --rosy <2|4|6>       Rotation symmetry type (default: 4)\n");
    printf("  -p, --posy <3|4>         Position symmetry type (default: 4)\n");
    printf("  -s, --scale <float>      Target edge length\n");
    printf("  -f, --faces <int>        Target face count\n");
    printf("  -v, --vertices <int>     Target vertex count\n");
    printf("  -c, --crease <degrees>   Crease angle threshold (default: -1 = auto)\n");
    printf("  -i, --intrinsic          Use intrinsic mode (default: extrinsic)\n");
    printf("  -b, --boundaries         Align to boundaries\n");
    printf("  -D, --dominant           Quad-dominant (not pure quad)\n");
    printf("  -S, --smooth <int>       Smoothing iterations (default: 2)\n");
    printf("  -d, --deterministic      Deterministic mode\n");
    printf("  -t, --threads <int>      Thread count (default: auto)\n");
    printf("  -h, --help               Show this help\n");
}

static bool load_glb(const char *path, MatrixXu &F, MatrixXf &V, MatrixXf &N) {
    cgltf_options options = {};
    cgltf_data *data = nullptr;
    cgltf_result res = cgltf_parse_file(&options, path, &data);
    if (res != cgltf_result_success) {
        fprintf(stderr, "Failed to parse GLB/glTF: %s\n", path);
        return false;
    }

    res = cgltf_load_buffers(&options, data, path);
    if (res != cgltf_result_success) {
        fprintf(stderr, "Failed to load GLB/glTF buffers\n");
        cgltf_free(data);
        return false;
    }

    // Collect all mesh primitives
    int total_verts = 0, total_indices = 0;
    for (size_t mi = 0; mi < data->meshes_count; mi++) {
        const cgltf_mesh &mesh = data->meshes[mi];
        for (size_t pi = 0; pi < mesh.primitives_count; pi++) {
            const cgltf_primitive &prim = mesh.primitives[pi];
            if (prim.type != cgltf_primitive_type_triangles) continue;

            cgltf_size count = 0;
            if (prim.indices)
                count = cgltf_accessor_unpack_indices(prim.indices, nullptr, sizeof(uint32_t), 0);
            else
                count = prim.attributes[0].data->count;

            total_verts += (int)count;
            total_indices += (int)(prim.indices ? prim.indices->count : count);
        }
    }

    if (total_verts == 0) {
        fprintf(stderr, "No triangle mesh data found in GLB/glTF\n");
        cgltf_free(data);
        return false;
    }

    V.resize(3, total_verts);
    F.resize(3, total_indices / 3);
    bool has_normals = false;

    int vert_offset = 0, tri_offset = 0, idx_offset = 0;
    for (size_t mi = 0; mi < data->meshes_count; mi++) {
        const cgltf_mesh &mesh = data->meshes[mi];
        for (size_t pi = 0; pi < mesh.primitives_count; pi++) {
            const cgltf_primitive &prim = mesh.primitives[pi];
            if (prim.type != cgltf_primitive_type_triangles) continue;

            // Read positions
            cgltf_size vcount = 0;
            float *pos_buf = nullptr;
            for (size_t ai = 0; ai < prim.attributes_count; ai++) {
                const cgltf_attribute &attr = prim.attributes[ai];
                if (attr.type == cgltf_attribute_type_position) {
                    vcount = attr.data->count;
                    pos_buf = new float[vcount * 3];
                    cgltf_accessor_unpack_floats(attr.data, pos_buf, vcount * 3);

                    for (cgltf_size i = 0; i < vcount; i++) {
                        V(0, vert_offset + (int)i) = pos_buf[i * 3 + 0];
                        V(1, vert_offset + (int)i) = pos_buf[i * 3 + 1];
                        V(2, vert_offset + (int)i) = pos_buf[i * 3 + 2];
                    }
                    delete[] pos_buf;
                } else if (attr.type == cgltf_attribute_type_normal) {
                    has_normals = true;
                }
            }

            // Read indices
            int icount = 0;
            if (prim.indices) {
                icount = (int)prim.indices->count;
                uint32_t *idx_buf = new uint32_t[icount];
                cgltf_accessor_unpack_indices(prim.indices, idx_buf, sizeof(uint32_t), icount);

                for (int i = 0; i < icount; i += 3) {
                    F(0, tri_offset + i/3) = idx_buf[i+0] + idx_offset;
                    F(1, tri_offset + i/3) = idx_buf[i+1] + idx_offset;
                    F(2, tri_offset + i/3) = idx_buf[i+2] + idx_offset;
                }
                tri_offset += icount / 3;
                delete[] idx_buf;
            } else {
                // Non-indexed geometry
                for (int i = 0; i < (int)vcount; i += 3) {
                    F(0, tri_offset + i/3) = (uint32_t)(i+0) + idx_offset;
                    F(1, tri_offset + i/3) = (uint32_t)(i+1) + idx_offset;
                    F(2, tri_offset + i/3) = (uint32_t)(i+2) + idx_offset;
                }
                tri_offset += (int)vcount / 3;
            }

            idx_offset += (int)vcount;
            vert_offset += (int)vcount;
        }
    }

    cgltf_free(data);

    // Compute normals if not present
    if (has_normals) {
        // Simple face-area-weighted normals
        N.resize(3, V.cols());
        N.setZero();
        for (int i = 0; i < (int)F.cols(); i++) {
            Vector3f p0 = V.col(F(0,i)), p1 = V.col(F(1,i)), p2 = V.col(F(2,i));
            Vector3f fn = (p1-p0).cross(p2-p0);
            Float area = fn.norm() * 0.5f;
            fn.normalize();
            for (int j = 0; j < 3; j++)
                N.col(F(j,i)) += fn * area;
        }
        for (int i = 0; i < (int)N.cols(); i++)
            N.col(i).normalize();
    } else {
        N.resize(3, V.cols());
        N.setZero();
        for (int i = 0; i < (int)F.cols(); i++) {
            Vector3f p0 = V.col(F(0,i)), p1 = V.col(F(1,i)), p2 = V.col(F(2,i));
            Vector3f fn = (p1-p0).cross(p2-p0);
            Float area = fn.norm() * 0.5f;
            fn.normalize();
            for (int j = 0; j < 3; j++)
                N.col(F(j,i)) += fn * area;
        }
        for (int i = 0; i < (int)N.cols(); i++)
            N.col(i).normalize();
    }

    printf("Loaded GLB/glTF: %d vertices, %d triangles\n",
           (int)V.cols(), (int)F.cols());
    return true;
}

static bool is_gltf(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) return false;
    return strcasecmp(ext, ".glb") == 0 || strcasecmp(ext, ".gltf") == 0;
}

int main(int argc, char **argv) {
    int rosy = 4, posy = 4, face_count = -1, vertex_count = -1;
    int smooth_iter = 2, knn_points = 10;
    Float crease_angle = -1, scale = -1;
    bool extrinsic = true, align_to_boundaries = false;
    bool pure_quad = true, deterministic = false;
    std::string input, output;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            print_usage(argv[0]);
            return 0;
        } else if (!strcmp(argv[i], "-r") || !strcmp(argv[i], "--rosy")) {
            if (++i >= argc) { fprintf(stderr, "Missing rosy value\n"); return 1; }
            rosy = atoi(argv[i]);
        } else if (!strcmp(argv[i], "-p") || !strcmp(argv[i], "--posy")) {
            if (++i >= argc) { fprintf(stderr, "Missing posy value\n"); return 1; }
            posy = atoi(argv[i]);
            if (posy == 6) posy = 3;
        } else if (!strcmp(argv[i], "-s") || !strcmp(argv[i], "--scale")) {
            if (++i >= argc) { fprintf(stderr, "Missing scale value\n"); return 1; }
            scale = (Float)atof(argv[i]);
        } else if (!strcmp(argv[i], "-f") || !strcmp(argv[i], "--faces")) {
            if (++i >= argc) { fprintf(stderr, "Missing face count\n"); return 1; }
            face_count = atoi(argv[i]);
        } else if (!strcmp(argv[i], "-v") || !strcmp(argv[i], "--vertices")) {
            if (++i >= argc) { fprintf(stderr, "Missing vertex count\n"); return 1; }
            vertex_count = atoi(argv[i]);
        } else if (!strcmp(argv[i], "-c") || !strcmp(argv[i], "--crease")) {
            if (++i >= argc) { fprintf(stderr, "Missing crease angle\n"); return 1; }
            crease_angle = (Float)atof(argv[i]);
        } else if (!strcmp(argv[i], "-i") || !strcmp(argv[i], "--intrinsic")) {
            extrinsic = false;
        } else if (!strcmp(argv[i], "-b") || !strcmp(argv[i], "--boundaries")) {
            align_to_boundaries = true;
        } else if (!strcmp(argv[i], "-D") || !strcmp(argv[i], "--dominant")) {
            pure_quad = false;
        } else if (!strcmp(argv[i], "-d") || !strcmp(argv[i], "--deterministic")) {
            deterministic = true;
        } else if (!strcmp(argv[i], "-S") || !strcmp(argv[i], "--smooth")) {
            if (++i >= argc) { fprintf(stderr, "Missing smooth iter count\n"); return 1; }
            smooth_iter = atoi(argv[i]);
        } else if (!strcmp(argv[i], "-t") || !strcmp(argv[i], "--threads")) {
            if (++i >= argc) { fprintf(stderr, "Missing thread count\n"); return 1; }
            nprocs = atoi(argv[i]);
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 1;
        } else if (input.empty()) {
            input = argv[i];
        } else if (output.empty()) {
            output = argv[i];
        } else {
            fprintf(stderr, "Too many arguments\n");
            return 1;
        }
    }

    if (input.empty() || output.empty()) {
        print_usage(argv[0]);
        return 1;
    }

    if (rosy != 2 && rosy != 4 && rosy != 6) {
        fprintf(stderr, "RoSy must be 2, 4, or 6\n");
        return 1;
    }
    if (posy != 3 && posy != 4) {
        fprintf(stderr, "PoSy must be 3 or 4\n");
        return 1;
    }

    printf("\nInstant Meshes CLI\n");
    printf("  Input:   %s\n", input.c_str());
    printf("  Output:  %s\n", output.c_str());
    printf("  RoSy:    %d\n", rosy);
    printf("  PoSy:    %d\n", posy == 3 ? 6 : posy);
    printf("  Mode:    %s\n", extrinsic ? "extrinsic" : "intrinsic");
    printf("  Output:  %s\n", pure_quad ? "pure quad" : "quad-dominant");

    // ---- Load ----
    MatrixXu F;
    MatrixXf V, N;
    printf("\nLoading... ");

    if (is_gltf(input.c_str())) {
        if (!load_glb(input.c_str(), F, V, N)) return 1;
    } else {
        try {
            load_mesh_or_pointcloud(input, F, V, N);
        } catch (const std::exception &e) {
            fprintf(stderr, "\nFailed: %s\n", e.what());
            return 1;
        }
        if (F.cols() == 0 && V.cols() == 0) {
            fprintf(stderr, "\nEmpty mesh\n");
            return 1;
        }
    }

    printf("%d vertices, %d faces\n", (int)V.cols(), (int)F.cols());

    // ---- Stats ----
    MeshStats stats = compute_mesh_stats(F, V, deterministic);
    printf("  BBox: [%.2f %.2f %.2f] - [%.2f %.2f %.2f]\n",
           stats.mAABB.min.x(), stats.mAABB.min.y(), stats.mAABB.min.z(),
           stats.mAABB.max.x(), stats.mAABB.max.y(), stats.mAABB.max.z());

    bool pointcloud = F.size() == 0;
    VectorXf A;
    AdjacencyMatrix adj = nullptr;
    BVH *bvh = nullptr;
    std::set<uint32_t> crease_in, crease_out;

    if (pointcloud) {
        bvh = new BVH(&F, &V, &N, stats.mAABB);
        bvh->build();
        adj = generate_adjacency_matrix_pointcloud(V, N, bvh, stats, knn_points, deterministic);
        A.resize(V.cols()); A.setConstant(1.0f);
    }

    // ---- Density ----
    if (scale < 0 && vertex_count < 0 && face_count < 0) {
        vertex_count = (int)V.cols() / 16;
        if (vertex_count < 100) vertex_count = 100;
    }
    if (scale > 0) {
        Float fa = posy == 4 ? (scale*scale) : (std::sqrt(3.f)/4.f*scale*scale);
        face_count = stats.mSurfaceArea / fa;
        vertex_count = posy == 4 ? face_count : (face_count/2);
    } else if (face_count > 0) {
        Float fa = stats.mSurfaceArea / face_count;
        vertex_count = posy == 4 ? face_count : (face_count/2);
        scale = posy == 4 ? std::sqrt(fa) : (2*std::sqrt(fa*std::sqrt(1.f/3.f)));
    } else if (vertex_count > 0) {
        face_count = posy == 4 ? vertex_count : (vertex_count*2);
        Float fa = stats.mSurfaceArea / face_count;
        scale = posy == 4 ? std::sqrt(fa) : (2*std::sqrt(fa*std::sqrt(1.f/3.f)));
    }

    printf("  Target: ~%d vertices, ~%d faces, edge %.3f\n",
           vertex_count, face_count, scale);

    // ---- Pipeline ----
    Timer<> timer;
    MultiResolutionHierarchy mRes;

    if (!pointcloud) {
        VectorXu V2E, E2E;
        VectorXb boundary, nonManifold;

        if (stats.mMaximumEdgeLength*2 > scale ||
            stats.mMaximumEdgeLength > stats.mAverageEdgeLength * 2) {
            printf("Subdividing...\n");
            build_dedge(F, V, V2E, E2E, boundary, nonManifold);
            subdivide(F, V, V2E, E2E, boundary, nonManifold,
                      std::min(scale/2, (Float)stats.mAverageEdgeLength*2),
                      deterministic);
        }

        build_dedge(F, V, V2E, E2E, boundary, nonManifold);
        adj = generate_adjacency_matrix_uniform(F, V2E, E2E, nonManifold);

        if (crease_angle >= 0)
            generate_crease_normals(F, V, V2E, E2E, boundary, nonManifold,
                                     crease_angle, N, crease_in);
        else
            generate_smooth_normals(F, V, V2E, E2E, nonManifold, N);

        compute_dual_vertex_areas(F, V, V2E, E2E, nonManifold, A);
        mRes.setE2E(std::move(E2E));
    }

    mRes.setAdj(std::move(adj));
    mRes.setF(std::move(F));
    mRes.setV(std::move(V));
    mRes.setA(std::move(A));
    mRes.setN(std::move(N));
    mRes.setScale(scale);
    mRes.build(deterministic);
    mRes.resetSolution();

    if (align_to_boundaries && !pointcloud) {
        mRes.clearConstraints();
        for (uint32_t i = 0; i < 3*mRes.F().cols(); i++) {
            if (mRes.E2E()[i] == INVALID) {
                uint32_t i0 = mRes.F()(i%3, i/3), i1 = mRes.F()((i+1)%3, i/3);
                Vector3f p0 = mRes.V().col(i0), p1 = mRes.V().col(i1);
                Vector3f edge = p1 - p0;
                if (edge.squaredNorm() > 0) {
                    edge.normalize();
                    mRes.CO().col(i0) = p0;
                    mRes.CO().col(i1) = p1;
                    mRes.CQ().col(i0) = mRes.CQ().col(i1) = edge;
                    mRes.CQw()[i0] = mRes.CQw()[i1] = 1.0f;
                    mRes.COw()[i0] = mRes.COw()[i1] = 1.0f;
                }
            }
        }
        mRes.propagateConstraints(rosy, posy);
    }

    if (bvh) {
    } else if (smooth_iter > 0) {
        bvh = new BVH(&mRes.F(), &mRes.V(), &mRes.N(), stats.mAABB);
        bvh->build();
    }

    printf("Preprocessing done. (%.1fs)\n", timer.reset());

    Optimizer optimizer(mRes, false);
    optimizer.setRoSy(rosy);
    optimizer.setPoSy(posy);
    optimizer.setExtrinsic(extrinsic);

    printf("Orientation field... "); fflush(stdout);
    optimizer.optimizeOrientations(-1);
    optimizer.notify(); optimizer.wait();
    printf("%.1fs\n", timer.reset());

    printf("Position field... "); fflush(stdout);
    optimizer.optimizePositions(-1);
    optimizer.notify(); optimizer.wait();
    printf("%.1fs\n", timer.reset());

    optimizer.shutdown();

    MatrixXf O_extr, N_extr, Nf_extr;
    std::vector<std::vector<TaggedLink>> adj_extr;
    printf("Extracting... "); fflush(stdout);
    extract_graph(mRes, extrinsic, rosy, posy, adj_extr,
                  O_extr, N_extr, crease_in, crease_out, deterministic);

    MatrixXu F_extr;
    extract_faces(adj_extr, O_extr, N_extr, Nf_extr, F_extr, posy,
                  mRes.scale(), crease_out, true, pure_quad, bvh, smooth_iter);
    printf("%.1fs\n", timer.reset());

    printf("Writing %d faces to %s...\n", (int)F_extr.cols(), output.c_str());
    write_mesh(output, F_extr, O_extr, MatrixXf(), Nf_extr);

    if (bvh) delete bvh;
    printf("Done.\n");
    return 0;
}
