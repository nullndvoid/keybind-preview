//! UI code for keybind-preview. Perhaps I should come up with a more interesting name.
//! UI should look nice as SVG cheatsheet/preview as well as interactive.
//! The designs should look roughly similar. Might need:
//! * Layout engine with something like elements.
//! * Font rendering engine.
//! * SVG/PNG renderer.
//!
//! Uses wl_shm (shared memory) + cairo image surface for rendering.
//! The pattern: create a shared-memory pool, map it, wrap the buffer with
//! cairo_image_surface_create_for_data, draw with cairo, then attach the
//! wl_buffer to the wl_surface and commit.

const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("cairo/cairo.h");
});

const View = @This();

// Wayland globals
wl_display: *c.wl_display,
wl_compositor: *c.wl_compositor,
wl_shm: *c.wl_shm,
wl_surface: *c.wl_surface,

// Buffer state
wl_buffer: ?*c.wl_buffer,
shm_fd: posix.fd_t,
shm_data: []align(4096) u8,
cairo_surface: *c.cairo_surface_t,
cairo: *c.cairo_t,

width: u31,
height: u31,
stride: u31,

pub const InitError = error{
    ConnectFailed,
    CompositorNotFound,
    ShmNotFound,
    SurfaceCreationFailed,
    ShmOpenFailed,
    MmapFailed,
    BufferCreationFailed,
    CairoSurfaceFailed,
    CairoContextFailed,
};

/// Connect to the Wayland display, bind globals, create a surface and
/// shared-memory buffer, and set up cairo for drawing.
pub fn init(width: u31, height: u31) InitError!View {
    // --- Wayland connection ---
    const wl_display = c.wl_display_connect(null) orelse return error.ConnectFailed;

    const registry = c.wl_display_get_registry(wl_display).?;
    var globals = Globals{};

    const registry_listener = c.wl_registry_listener{
        .global = &registryGlobal,
        .global_remove = &registryGlobalRemove,
    };
    _ = c.wl_registry_add_listener(registry, &registry_listener, @ptrCast(&globals));
    _ = c.wl_display_roundtrip(wl_display);

    const wl_compositor = globals.wl_compositor orelse return error.CompositorNotFound;
    const wl_shm = globals.wl_shm orelse return error.ShmNotFound;

    const wl_surface = c.wl_compositor_create_surface(wl_compositor) orelse return error.SurfaceCreationFailed;

    // --- Shared memory buffer ---
    const stride: u31 = width * 4; // ARGB32 = 4 bytes/pixel
    const buf_size: usize = @as(usize, stride) * @as(usize, height);

    const shm_fd = createShmFile(buf_size) catch return error.ShmOpenFailed;

    const shm_data = posix.mmap(
        null,
        buf_size,
        .{ .read = true, .write = true },
        .{ .TYPE = .SHARED },
        shm_fd,
        0,
    ) catch return error.MmapFailed;

    const pool = c.wl_shm_create_pool(wl_shm, shm_fd, @intCast(buf_size)) orelse return error.BufferCreationFailed;
    const wl_buffer = c.wl_shm_pool_create_buffer(
        pool,
        0,
        width,
        height,
        stride,
        c.WL_SHM_FORMAT_ARGB8888,
    ) orelse return error.BufferCreationFailed;
    c.wl_shm_pool_destroy(pool);

    // --- Cairo ---
    const cairo_surface = c.cairo_image_surface_create_for_data(
        shm_data.ptr,
        c.CAIRO_FORMAT_ARGB32,
        width,
        height,
        stride,
    ) orelse return error.CairoSurfaceFailed;

    if (c.cairo_surface_status(cairo_surface) != c.CAIRO_STATUS_SUCCESS)
        return error.CairoSurfaceFailed;

    const cr = c.cairo_create(cairo_surface) orelse return error.CairoContextFailed;

    if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS)
        return error.CairoContextFailed;

    return .{
        .wl_display = wl_display,
        .wl_compositor = wl_compositor,
        .wl_shm = wl_shm,
        .wl_surface = wl_surface,
        .wl_buffer = wl_buffer,
        .shm_fd = shm_fd,
        .shm_data = @alignCast(shm_data[0..buf_size]),
        .cairo_surface = cairo_surface,
        .cairo = cr,
        .width = width,
        .height = height,
        .stride = stride,
    };
}

/// Commit the current cairo drawing to the Wayland surface.
pub fn commit(self: *View) void {
    c.cairo_surface_flush(self.cairo_surface);
    c.wl_surface_attach(self.wl_surface, self.wl_buffer, 0, 0);
    c.wl_surface_damage_buffer(self.wl_surface, 0, 0, self.width, self.height);
    c.wl_surface_commit(self.wl_surface);
    _ = c.wl_display_flush(self.wl_display);
}

pub fn deinit(self: *View) void {
    c.cairo_destroy(self.cairo);
    c.cairo_surface_destroy(self.cairo_surface);

    if (self.wl_buffer) |buf| c.wl_buffer_destroy(buf);
    posix.munmap(self.shm_data);
    posix.close(self.shm_fd);

    c.wl_surface_destroy(self.wl_surface);
    c.wl_display_disconnect(self.wl_display);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create an anonymous shared-memory file of the given size using memfd_create
/// (or shm_open as fallback).
fn createShmFile(size: usize) !posix.fd_t {
    const fd = try posix.memfd_create("keybind-preview-shm", .{});
    try posix.ftruncate(fd, @intCast(size));
    return fd;
}

// ---------------------------------------------------------------------------
// Wayland registry
// ---------------------------------------------------------------------------

const Globals = struct {
    wl_compositor: ?*c.wl_compositor = null,
    wl_shm: ?*c.wl_shm = null,
};

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
    interface: [*:0]const u8,
    version: u32,
) callconv(.c) void {
    _ = version;
    const globals: *Globals = @ptrCast(@alignCast(data));
    if (std.mem.orderZ(u8, interface, "wl_compositor") == .eq) {
        globals.wl_compositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_compositor_interface,
            4,
        ));
    } else if (std.mem.orderZ(u8, interface, "wl_shm") == .eq) {
        globals.wl_shm = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_shm_interface,
            1,
        ));
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}
