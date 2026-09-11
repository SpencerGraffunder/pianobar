# Host-side debug/verification tools

Standalone C/ObjC programs that run directly on macOS (not on the
simulator) for quickly verifying the shims without a full xcodebuild
cycle. Each has its own `main()` and is therefore NOT part of the
Xcode test target (which is why they live outside Tests/).

Compile from this directory, e.g.:

    clang -fobjc-arc -I ../Shim -I ../../src -I ../../src/libpiano \
        -o bf host_debug_bf.c ../Shim/gcrypt_impl.c \
        -framework Security -framework Foundation && ./bf

(Adjust the file list per program; the .m ones need Foundation.)
