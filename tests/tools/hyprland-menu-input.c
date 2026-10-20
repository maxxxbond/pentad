#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const struct wl_message pointer_requests[] = {
    {"motion", "uff", NULL}, {"motion_absolute", "uuuuu", NULL},
    {"button", "uuu", NULL}, {"axis", "uuf", NULL}, {"frame", "", NULL},
    {"axis_source", "u", NULL}, {"axis_stop", "uu", NULL},
    {"axis_discrete", "uufi", NULL}, {"destroy", "", NULL},
};
static const struct wl_interface pointer_interface = {"zwlr_virtual_pointer_v1", 1, 9, pointer_requests, 0, NULL};
static const struct wl_interface *create_types[] = {&wl_seat_interface, &pointer_interface};
static const struct wl_message manager_requests[] = {
    {"create_virtual_pointer", "?on", create_types}, {"destroy", "", NULL},
};
static const struct wl_interface manager_interface = {"zwlr_virtual_pointer_manager_v1", 1, 2, manager_requests, 0, NULL};
static struct wl_proxy *manager;
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, manager_interface.name)) manager = wl_registry_bind(registry, name, &manager_interface, 1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener listener = {global, removed};
static uint32_t now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
}
int main(int argc, char **argv) {
    const char *display_name = getenv("WAYLAND_DISPLAY"), *headless = getenv("PENTAD_HEADLESS");
    if (argc != 3 || !headless || strcmp(headless, "1") || !display_name || strncmp(display_name, "/tmp/ph-", 8)) {
        fprintf(stderr, "Only the disposable nested Hyprland is allowed.\n"); return 2;
    }
    uint32_t width = atoi(argv[1]), height = atoi(argv[2]);
    if (!width || !height) return 2;
    struct wl_display *display = wl_display_connect(display_name);
    if (!display) return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) { fprintf(stderr, "Private compositor lacks virtual pointer protocol.\n"); return 4; }
    struct wl_proxy *pointer = wl_proxy_marshal_flags(manager, 0, &pointer_interface, 1, 0, NULL, NULL);
    wl_display_roundtrip(display);
    setvbuf(stdout, NULL, _IOLBF, 0); puts("ready");
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        double x, y; unsigned int button;
        if (sscanf(line, "move %lf %lf", &x, &y) == 2) {
            wl_proxy_marshal_flags(pointer, 1, NULL, 1, 0, now(), (uint32_t)(x * 1024), (uint32_t)(y * 1024), width * 1024, height * 1024);
        } else if (sscanf(line, "click %u", &button) == 1) {
            wl_proxy_marshal_flags(pointer, 2, NULL, 1, 0, now(), button, 1u);
            wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0); wl_display_flush(display); usleep(30000);
            wl_proxy_marshal_flags(pointer, 2, NULL, 1, 0, now(), button, 0u);
        } else if (sscanf(line, "scroll %lf", &y) == 1) {
            wl_proxy_marshal_flags(pointer, 3, NULL, 1, 0, now(), 0u, wl_fixed_from_double(y));
        } else if (!strncmp(line, "quit", 4)) break;
        else return 5;
        wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0); wl_display_roundtrip(display);
    }
    wl_proxy_marshal_flags(pointer, 8, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_proxy_marshal_flags(manager, 1, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_registry_destroy(registry); wl_display_flush(display); wl_display_disconnect(display);
    return 0;
}
