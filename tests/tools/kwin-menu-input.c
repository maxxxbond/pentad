#include <gio/gio.h>
#include <libei.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static uint64_t now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}
static void frame(struct ei *context, struct ei_device *device) {
    ei_device_frame(device, now()); ei_dispatch(context);
}
int main(int argc, char **argv) {
    (void)argv;
    const char *display_name = getenv("WAYLAND_DISPLAY"), *headless = getenv("PENTAD_HEADLESS");
    const char *bus_address = getenv("DBUS_SESSION_BUS_ADDRESS"), *bus_socket = getenv("PENTAD_PRIVATE_DBUS_SOCKET");
    if (argc != 1 || !headless || strcmp(headless, "1") || !display_name || !strstr(display_name, "/pentad-test-virtual")) {
        fprintf(stderr, "Only the disposable Pentad test compositor is allowed.\n"); return 2;
    }
    if (!bus_address || !bus_socket || !strstr(bus_socket, "/pentad-headless-") || strncmp(bus_address, "unix:path=", 10)
            || strncmp(bus_address + 10, bus_socket, strlen(bus_socket)) || bus_address[10 + strlen(bus_socket)] != ',') {
        fprintf(stderr, "Only the explicitly created private test D-Bus socket is allowed.\n"); return 2;
    }
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) { fprintf(stderr, "%s\n", error->message); return 3; }
    GUnixFDList *fds = NULL;
    GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(bus,
        "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop", "connectToEIS",
        g_variant_new("(i)", 2), G_VARIANT_TYPE("(hi)"), G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &fds, NULL, &error);
    if (!reply) { fprintf(stderr, "%s\n", error->message); return 4; }
    int index, cookie; g_variant_get(reply, "(hi)", &index, &cookie);
    int fd = g_unix_fd_list_get(fds, index, &error);
    if (fd < 0) return 5;
    struct ei *context = ei_new_sender(NULL);
    ei_configure_name(context, "Pentad isolated menu input");
    if (ei_setup_backend_fd(context, fd) != 0) return 6;
    struct ei_device *pointer = NULL;
    uint64_t deadline = now() + 3000000;
    while (!pointer && now() < deadline) {
        struct pollfd p = { ei_get_fd(context), POLLIN, 0 }; poll(&p, 1, 50);
        ei_dispatch(context);
        struct ei_event *event;
        while ((event = ei_get_event(context))) {
            enum ei_event_type type = ei_event_get_type(event);
            if (type == EI_EVENT_SEAT_ADDED) {
                ei_seat_bind_capabilities(ei_event_get_seat(event), EI_DEVICE_CAP_POINTER_ABSOLUTE, EI_DEVICE_CAP_BUTTON, EI_DEVICE_CAP_SCROLL, NULL);
            } else if (type == EI_EVENT_DEVICE_RESUMED) {
                struct ei_device *device = ei_event_get_device(event);
                if (ei_device_has_capability(device, EI_DEVICE_CAP_POINTER_ABSOLUTE) && ei_device_has_capability(device, EI_DEVICE_CAP_BUTTON))
                    pointer = ei_device_ref(device);
            }
            ei_event_unref(event);
        }
    }
    if (!pointer) { fprintf(stderr, "Private compositor did not resume an absolute pointer.\n"); return 7; }
    ei_device_start_emulating(pointer, 1);
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("ready");
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        double x, y;
        unsigned int button;
        if (sscanf(line, "move %lf %lf", &x, &y) == 2) {
            ei_device_pointer_motion_absolute(pointer, x, y); frame(context, pointer);
        } else if (sscanf(line, "click %u", &button) == 1) {
            ei_device_button_button(pointer, button, true); frame(context, pointer); usleep(30000);
            ei_device_button_button(pointer, button, false); frame(context, pointer);
        } else if (sscanf(line, "scroll %lf", &y) == 1) {
            ei_device_scroll_delta(pointer, 0, y); frame(context, pointer);
        } else if (!strncmp(line, "quit", 4)) break;
        else { fprintf(stderr, "Unknown input command: %s", line); return 8; }
    }
    ei_device_stop_emulating(pointer); ei_dispatch(context);
    ei_device_unref(pointer); ei_unref(context);
    g_dbus_connection_call_sync(bus, "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop",
        "disconnect", g_variant_new("(i)", cookie), NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, NULL);
    g_object_unref(bus);
    return 0;
}
