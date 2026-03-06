#!/bin/bash
set -e

# 工作目录设置为 /data (Docker 挂载点)
cd /data

BUILD_DIR=build_switch

# 1. 安装必要的 Switch 开发包
echo "Installing Switch dependencies..."
dkp-pacman -S --noconfirm \
    switch-dev \
    switch-sdl2 \
    switch-sdl2_image \
    switch-sdl2_ttf \
    switch-mesa \
    switch-libdrm_nouveau \
    switch-ffmpeg \
    switch-libmpv \
    switch-libtheora \
    switch-libvorbis \
    switch-libwebp \
    switch-pkg-config

# 2. 清理旧的编译目录
echo "Cleaning up build directory..."
# 在 Docker 中运行，如果频繁重建，建议只清理 build 缓存
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}

# 3. 配置 CMake (只生成 ELF)
echo "Configuring CMake for Nintendo Switch..."
cmake -G "Unix Makefiles" \
    -B ${BUILD_DIR} \
    -DCMAKE_TOOLCHAIN_FILE=/opt/devkitpro/cmake/Switch.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DPLATFORM_SWITCH=ON \
    -DPLATFORM_DESKTOP=OFF \
    -DUSE_SDL2=ON

# 4. 执行编译
echo "Building ELF..."
cmake --build ${BUILD_DIR} -j$(nproc)

# 5. 手动打包 NRO (使用修复后的 --romfsdir)
echo "----------------------------------------------------"
echo "Packaging NRO with debug logs enabled..."

ELF_FILE="${BUILD_DIR}/Lorealis.elf"
NRO_FILE="${BUILD_DIR}/Lorealis.nro"

if [ -f "$ELF_FILE" ]; then
    # 同步 RomFS 资源到本地目录 (解决 Docker 属性问题)
    echo "Syncing RomFS assets..."
    rm -rf /tmp/romfs_final
    mkdir -p /tmp/romfs_final
    tar -C res -cf - . | tar -C /tmp/romfs_final -xf -
    
    # 移除可能引起干扰的文件
    find /tmp/romfs_final -name ".gitignore" -delete

    echo "Running elf2nro..."
    elf2nro "$ELF_FILE" "$NRO_FILE" \
        --icon=res/img/demo_icon.jpg \
        --name="Lorealis" \
        --author="ns-chat" \
        --romfsdir=/tmp/romfs_final
    
    # 清理
    rm -rf /tmp/romfs_final
else
    echo "ERROR: ELF build failed."
    exit 1
fi

echo "----------------------------------------------------"
echo "Build Finished!"
if [ -f "$NRO_FILE" ]; then
    echo "SUCCESS: The NRO file is ready at '$NRO_FILE'"
    echo "ADVICE: Run 'nxlink -s' on your PC to catch the startup logs!"
else
    echo "ERROR: NRO file generation failed."
    exit 1
fi
echo "----------------------------------------------------"
