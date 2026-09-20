export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/30.0.15729638
export PATH=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
cargo build --release --target aarch64-linux-android
