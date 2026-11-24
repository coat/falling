# falling

A remake of NS-SHAFT.

## Controls

| Button | Action |
|--|--|
| D-Pad Left | Left |
| D-Pad Right | Right |
| Start | Pause |

## Building

Built with Zig from <https://github.com/coat/falling>:

```sh
zig build -Dportmaster
```

The package directory is assembled in `zig-out/portmaster`. The binary links
SDL3 statically and needs no bundled libraries as it uses SDL's own video
drivers where the firmware supports them (kmsdrm on Mesa-based firmwares) and
falls back to the vendor EGL null-window-system blobs (`libEGL.so.1`,
`libGLESv2.so.2`) on devices without a KMS display stack, like the TrimUI
Brick.
