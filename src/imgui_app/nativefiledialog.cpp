#include "nativefiledialog.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static std::string run_applescript(const std::string &script) {
    // Write script to temp file
    std::string tmp_script = "/tmp/im_script.applescript";
    std::string tmp_out = "/tmp/im_fd_result.txt";

    FILE *fs = fopen(tmp_script.c_str(), "w");
    if (!fs) return "";
    fputs(script.c_str(), fs);
    fclose(fs);

    std::string cmd = "osascript \"" + tmp_script + "\" > \"" + tmp_out + "\" 2>/dev/null";
    system(cmd.c_str());
    remove(tmp_script.c_str());

    FILE *fr = fopen(tmp_out.c_str(), "r");
    if (!fr) return "";
    char buf[4096] = {};
    fread(buf, 1, sizeof(buf)-1, fr);
    fclose(fr);
    remove(tmp_out.c_str());

    std::string result(buf);
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        result.pop_back();
    return result;
}

char *native_open_dialog(const char **extensions) {
    std::string type_list = "{";
    if (extensions) {
        bool first = true;
        for (int i = 0; extensions[i]; i++) {
            if (!first) type_list += ", ";
            first = false;
            std::string ext(extensions[i]);
            if (ext == "obj") type_list += "\"public.obj\"";
            else if (ext == "ply") type_list += "\"public.ply\"";
            else if (ext == "aln") type_list += "\"public.plain-text\"";
            else type_list += "\"public.data\"";
        }
    }
    if (type_list == "{") type_list += "\"public.data\"";
    type_list += "}";

    std::string script =
        "try\n"
        "    set f to choose file of type " + type_list + " with prompt \"Open Mesh\"\n"
        "    return POSIX path of f\n"
        "on error\n"
        "    try\n"
        "        set f to choose file with prompt \"Open Mesh\"\n"
        "        return POSIX path of f\n"
        "    on error\n"
        "        return \"\"\n"
        "    end try\n"
        "end try\n";

    std::string path = run_applescript(script);
    if (path.empty()) return nullptr;
    return strdup(path.c_str());
}

char *native_save_dialog(const char *default_name) {
    std::string name = default_name ? default_name : "remeshed.obj";
    std::string script =
        "try\n"
        "    set f to choose file name with prompt \"Export Mesh\" default name \"" + name + "\"\n"
        "    return POSIX path of f\n"
        "on error\n"
        "    return \"\"\n"
        "end try\n";

    std::string path = run_applescript(script);
    if (path.empty()) return nullptr;
    return strdup(path.c_str());
}
