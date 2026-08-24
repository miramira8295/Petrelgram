# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(Petrelgram)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# Keep the build machine out of the shipped binary. Linking against the
# imported libtdjson.so otherwise records its directory — an absolute path on
# the developer's disk — as RUNPATH, and __FILE__ in any assertion would bake
# in the source path. Both are visible to anyone running `strings` on a
# released HAP. RUNPATH is useless at runtime anyway: the loader resolves
# DT_NEEDED from the HAP's own libs directory.
set(CMAKE_SKIP_BUILD_RPATH TRUE)
set(CMAKE_SKIP_INSTALL_RPATH TRUE)
add_compile_options(-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED napi_init.cpp webm_alpha.cpp webm_alpha_napi.cpp)

add_library(tdjson SHARED IMPORTED)
set_target_properties(tdjson PROPERTIES IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libtdjson.so)

add_library(tgcalls_ohos SHARED IMPORTED)
set_target_properties(tgcalls_ohos PROPERTIES IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libtgcalls_ohos.so)

# 透明 webm 贴纸的 VP9 软解码器。**随包自带，不用系统的。**
#
# 系统 AVCodec 在实测的海思设备上根本没有 VP9（枚举 19 个视频解码器，VP9/VP8
# 软硬解都没有），整条链路一次都没跑起来。贴纸是 512px/30fps/3s/256KB 的小东西，
# 软解绰绰有余，不值得为它赌设备能力。产物由 scripts/build-libvpx-ohos.sh 生成。
set(LIBVPX_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/libvpx-ohos)
if(NOT EXISTS ${LIBVPX_DIR}/${OHOS_ARCH}/libvpx.a)
    message(FATAL_ERROR
        "缺 libvpx：先跑 bash scripts/build-libvpx-ohos.sh（产物不进版本库）")
endif()
add_library(vpx STATIC IMPORTED)
set_target_properties(vpx PROPERTIES IMPORTED_LOCATION
    ${LIBVPX_DIR}/${OHOS_ARCH}/libvpx.a)
target_include_directories(entry PRIVATE ${LIBVPX_DIR}/include)

# libpixelmap 仍要：合成出来的 RGBA 要交给 PixelMap。
# libnative_media_* 三个已经摘掉——换成 libvpx 之后不再碰系统解码器。
target_link_libraries(entry PUBLIC libace_napi.z.so tdjson tgcalls_ohos libhilog_ndk.z.so
    vpx libpixelmap.so)
