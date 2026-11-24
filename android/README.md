# android

As recommended in the "Building a more complex app" section from the
[README-android](https://wiki.libsdl.org/SDL3/README-android), we copy all the
[glue
code](https://github.com/libsdl-org/SDL/tree/release-3.4.12/android-project/app/src/main)
from the same version of
[SDL](https://github.com/libsdl-org/SDL/tree/release-3.4.12) we are using into
our repository.

`zig build -Dandroid` will build `./zig-out/bin/falling.apk`.

`zig build -Dandroid run` will install and run on a connected android device.

## references

- [README-android](https://wiki.libsdl.org/SDL3/README-android)
- [zig-android-sdk example](https://github.com/silbinarywolf/zig-android-sdk/tree/main/examples/minimal)
