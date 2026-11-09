if(NOT DEFINED TGCALLS_SOURCE_DIR OR NOT DEFINED TGCALLS_BRIDGE_SOURCE OR
   NOT DEFINED OHOS_WEBRTC_OBJ_DIR OR NOT DEFINED OHOS_WEBRTC_SOURCE_DIR)
    message(FATAL_ERROR "TGCALLS_SOURCE_DIR, TGCALLS_BRIDGE_SOURCE, OHOS_WEBRTC_OBJ_DIR and OHOS_WEBRTC_SOURCE_DIR are required")
endif()

add_library(tgcalls_group STATIC
    ${TGCALLS_SOURCE_DIR}/tgcalls/AudioDeviceHelper.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/ChannelManager.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/CodecSelectHelper.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/FakeAudioDeviceModule.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/FieldTrialsConfig.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/LogSinkImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/SctpDataChannelProviderInterfaceImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/StaticThreads.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/TurnCustomizerImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/VideoCaptureInterface.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/VideoCaptureInterfaceImpl.cpp
    # 1:1 通话（Instance / InstanceV2）。
    ${TGCALLS_SOURCE_DIR}/tgcalls/CryptoHelper.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/EncryptedConnection.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/Instance.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/InstanceImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/Manager.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/MediaManager.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/Message.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/NetworkManager.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/ContentNegotiation.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/DirectNetworkingImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/ExternalSignalingConnection.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/InstanceV2Impl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/InstanceV2ReferenceImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/NativeNetworkingImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/ReflectorPort.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/ReflectorRelayPortFactory.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/Signaling.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/SignalingConnection.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/SignalingEncryption.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/v2/SignalingSctpConnection.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/utils/gzip.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/AVIOContextImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/AudioStreamingPart.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/AudioStreamingPartInternal.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/AudioStreamingPartPersistentDecoder.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/GroupInstanceCustomImpl.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/GroupJoinPayloadInternal.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/GroupNetworkManager.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/StreamingMediaContext.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/group/VideoStreamingPart.cpp
    ${CMAKE_CURRENT_LIST_DIR}/tgcalls_ohos_platform.cpp
    ${CMAKE_CURRENT_LIST_DIR}/tgcalls_ohos_local_video.cpp
    ${OHOS_WEBRTC_SOURCE_DIR}/desktop_capture/desktop_capturer.cpp
    ${OHOS_WEBRTC_SOURCE_DIR}/helper/camera.cpp
    ${TGCALLS_SOURCE_DIR}/tgcalls/third-party/json11.cpp
)
target_include_directories(tgcalls_group PUBLIC
    ${TGCALLS_SOURCE_DIR}
    ${TGCALLS_SOURCE_DIR}/tgcalls
    ${OHOS_WEBRTC_SOURCE_DIR}
)
target_compile_definitions(tgcalls_group PRIVATE
    TGCALLS_USE_STD_OPTIONAL
    USE_RNNOISE=0
    NDK_HELPER_DISABLE_CPP_EXCEPTIONS
)
target_link_libraries(tgcalls_group PUBLIC tg_owt)
link_ffmpeg(tgcalls_group)
link_opus(tgcalls_group)
link_openssl(tgcalls_group)

add_library(tgcalls_ohos SHARED ${TGCALLS_BRIDGE_SOURCE})
target_include_directories(tgcalls_ohos PRIVATE
    ${TGCALLS_SOURCE_DIR}
    ${TGCALLS_SOURCE_DIR}/tgcalls
)

# The GN archives contain thin references to architecture-specific loose
# objects, so link those objects explicitly into the final shared library.
set(BORINGSSL_ASM_DIR ${OHOS_WEBRTC_OBJ_DIR}/third_party/boringssl/boringssl_asm)
file(GLOB BORINGSSL_ARM64_ASM_OBJECTS "${BORINGSSL_ASM_DIR}/*armv8-linux.o")
list(APPEND BORINGSSL_ARM64_ASM_OBJECTS
    ${BORINGSSL_ASM_DIR}/armv8-mont-linux.o
    ${BORINGSSL_ASM_DIR}/poly_rq_mul.o
    ${BORINGSSL_ASM_DIR}/poly1305_arm_asm.o
    ${BORINGSSL_ASM_DIR}/x25519-asm-arm.o
)
set(LIBVPX_OBJ_DIR ${OHOS_WEBRTC_OBJ_DIR}/third_party/libvpx)
file(GLOB LIBVPX_ARM64_OBJECTS
    "${LIBVPX_OBJ_DIR}/libvpx_intrinsics_neon/*.o"
    "${LIBVPX_OBJ_DIR}/libvpx_intrinsics_neon_dotprod/*.o"
    "${LIBVPX_OBJ_DIR}/libvpx_intrinsics_neon_i8mm/*.o"
)

target_link_libraries(tgcalls_ohos PRIVATE
    tgcalls_group
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/ffmpeg/libffmpeg_internal.a
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/opus/libopus.a
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/boringssl/libboringssl.a
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/libvpx/libvpx.a
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/libjpeg_turbo/libjpeg.a
    ${OHOS_WEBRTC_OBJ_DIR}/third_party/libjpeg_turbo/libsimd.a
    ${BORINGSSL_ARM64_ASM_OBJECTS}
    ${LIBVPX_ARM64_OBJECTS}
    libohaudio.so
    libhilog_ndk.z.so
    libohcamera.so
    libohimage.so
    libimage_receiver.so
    libnative_buffer.so
    libnative_window.so
    libnative_avscreen_capture.so
    libnative_media_core.so
    # tgcalls/utils/gzip.cpp（1:1 v2 信令压缩）依赖系统 zlib。
    libz.so
)
