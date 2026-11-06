# Keep this NDK in lock-step with the Android export template. Godot ships its
# own libc++_shared.so; building with a newer NDK can reference libc++ symbols
# that the template does not export (e.g. __hash_memory from NDK 30), making
# the whole GDExtension fail to load on device.
NDK_VERSION="${ANDROID_NDK_VERSION:-29.0.14206865}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/$NDK_VERSION}"
export PATH=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
cargo build --release --target aarch64-linux-android
