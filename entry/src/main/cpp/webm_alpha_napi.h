#ifndef PETRELGRAM_WEBM_ALPHA_NAPI_H
#define PETRELGRAM_WEBM_ALPHA_NAPI_H

#include "napi/native_api.h"

// 把透明贴纸的两个接口挂到 libentry 的 exports 上。
// 单独一个文件是因为 napi_init.cpp 已经很长，再往里塞会越过项目的文件上限。
void WebmAlphaRegister(napi_env env, napi_value exports);

#endif // PETRELGRAM_WEBM_ALPHA_NAPI_H
