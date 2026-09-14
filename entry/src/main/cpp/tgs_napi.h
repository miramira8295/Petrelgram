#ifndef PETRELGRAM_TGS_NAPI_H
#define PETRELGRAM_TGS_NAPI_H

#include "napi/native_api.h"

// TGS 原生渲染的三个接口挂到 libentry 的 exports 上。
void TgsRegister(napi_env env, napi_value exports);

#endif // PETRELGRAM_TGS_NAPI_H
