import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { logE, logW } from '../util/log';

// WEB 代理 secret 的安全存放。
//
// 为什么需要它：secret 是部署侧 tproxy-server 的登录凭据（能冒充你的 Web 代理），
// 早先和 host/path 一起 JSON.stringify 明文进 preferences，root 之外任何能读
// /data/app/el2/.../base/preferences 的东西都能拿到。这里改成 HUKS 托管密钥的
// AES-256-GCM：密钥由 HUKS 生成并保管（alias 见下），进程只拿密文，自己不接触密钥；
// 换机、清应用数据、HUKS 密钥被系统回收都会让密文解不开——那时上层退回「未配置」，
// 不会出现「界面显示已连接但永远握不上手」。
//
// 分层：本文件只做「字符串 ↔ 密文字符串」，不碰 AppStorage/preferences，
// 免得和 store/AppSettings 形成循环 import。
const SECRET_KEY_ALIAS: string = 'petrel_web_proxy_secret_v1';
const GCM_NONCE_BYTES: number = 12;
// HUKS 的 AES-GCM 把认证标签追加在密文尾部，长度固定 16 字节（官方 AES/GCM/NoPadding 案例：
// 解密时 properties 里 HUKS_TAG_AE_TAG 传 cipherData.slice(len-16)，inData 传去掉标签的密文）。
const GCM_TAG_BYTES: number = 16;
const SEALED_VERSION: number = 1;

interface SealedSecretBlob {
  v: number;
  iv: string;
  ct: string;
}

function encodeText(text: string): Uint8Array {
  const encoder: util.TextEncoder = new util.TextEncoder();
  return encoder.encodeInto(text);
}

function decodeText(bytes: Uint8Array): string {
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(bytes);
}

function encodeBase64(bytes: Uint8Array): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  return helper.encodeToStringSync(bytes);
}

function decodeBase64(text: string): Uint8Array {
  const helper: util.Base64Helper = new util.Base64Helper();
  return helper.decodeSync(text);
}

function randomNonce(): Uint8Array {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const blob: cryptoFramework.DataBlob = random.generateRandomSync(GCM_NONCE_BYTES);
  return blob.data;
}

function errorText(err: Object): string {
  const be: BusinessError = err as BusinessError;
  const code: number = be.code;
  const detail: string = be.message;
  return code === undefined ? detail : code + ' ' + detail;
}

// 建密钥与加解密共用的基础属性。GCM 不需要 padding（HUKS 要求显式 NONE）。
function keyProperties(): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
  ];
  return properties;
}

// 参数表逐项对齐官方 AES/GCM/NoPadding 案例：少了 KEY_SIZE 或 AE_TAG 时 HUKS 会在
// TEE 里直接失败（真机表现：unseal failed: 12000xxx / TEEC ret 0xffffffe2）。
function ceremonyOptions(nonce: Uint8Array, purpose: number, data: Uint8Array,
  tag: Uint8Array | null): huks.HuksOptions {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
  ];
  if (tag !== null) {
    properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
  }
  const options: huks.HuksOptions = { properties: properties, inData: data };
  return options;
}

async function ensureKey(): Promise<boolean> {
  const options: huks.HuksOptions = { properties: keyProperties() };
  try {
    const exists: boolean = await huks.isKeyItemExist(SECRET_KEY_ALIAS, options);
    if (exists) {
      return true;
    }
  } catch (err) {
    // isKeyItemExist 失败不致命：下面 generateKeyItem 会给出真正的结论。
    logW('[WebProxyVault] probe key failed: ' + errorText(err));
  }
  try {
    await huks.generateKeyItem(SECRET_KEY_ALIAS, options);
    return true;
  } catch (err) {
    // 两个初始化路径并发时会撞 12000017（alias 已存在），再查一次即可。
    try {
      const exists: boolean = await huks.isKeyItemExist(SECRET_KEY_ALIAS, options);
      if (exists) {
        return true;
      }
    } catch (probeErr) {
      logW('[WebProxyVault] re-probe key failed: ' + errorText(probeErr));
    }
    logE('[WebProxyVault] generate key failed: ' + errorText(err));
    return false;
  }
}

// 返回空串表示「没有封成」：调用方必须把它当作失败处理（保留旧值或提示），
// 不能把空串当成「secret 就是空的」写进配置。
export async function sealWebProxySecret(secret: string): Promise<string> {
  if (secret.length === 0) {
    return '';
  }
  const ready: boolean = await ensureKey();
  if (!ready) {
    return '';
  }
  const nonce: Uint8Array = randomNonce();
  const plain: Uint8Array = encodeText(secret);
  const options: huks.HuksOptions = ceremonyOptions(nonce, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, plain, null);
  let handle: huks.HuksSessionHandle | null = null;
  try {
    handle = await huks.initSession(SECRET_KEY_ALIAS, options);
    const result: huks.HuksReturnResult = await huks.finishSession(handle.handle, options);
    const cipher: Uint8Array | undefined = result.outData;
    if (cipher === undefined || cipher.length === 0) {
      logE('[WebProxyVault] seal produced no ciphertext');
      return '';
    }
    const sealed: SealedSecretBlob = { v: SEALED_VERSION, iv: encodeBase64(nonce), ct: encodeBase64(cipher) };
    return JSON.stringify(sealed);
  } catch (err) {
    logE('[WebProxyVault] seal failed: ' + errorText(err));
    return '';
  }
}

// 返回空串表示「解不开」：可能是换机/清数据/密文损坏，也可能 HUKS 不可用。
export async function unsealWebProxySecret(blob: string): Promise<string> {
  if (blob.length === 0) {
    return '';
  }
  let parsed: SealedSecretBlob | null = null;
  try {
    parsed = JSON.parse(blob) as SealedSecretBlob;
  } catch (err) {
    logW('[WebProxyVault] sealed blob is not json');
    return '';
  }
  if (parsed === null || parsed.v !== SEALED_VERSION || parsed.iv.length === 0 || parsed.ct.length === 0) {
    logW('[WebProxyVault] sealed blob is not usable');
    return '';
  }
  let nonce: Uint8Array | null = null;
  let cipher: Uint8Array | null = null;
  try {
    nonce = decodeBase64(parsed.iv);
    cipher = decodeBase64(parsed.ct);
  } catch (err) {
    logW('[WebProxyVault] sealed blob is not base64');
    return '';
  }
  if (nonce === null || cipher === null) {
    return '';
  }
  if (cipher.length <= GCM_TAG_BYTES) {
    logW('[WebProxyVault] sealed blob is truncated');
    return '';
  }
  const tagAt: number = cipher.length - GCM_TAG_BYTES;
  const tag: Uint8Array = cipher.slice(tagAt);
  const body: Uint8Array = cipher.slice(0, tagAt);
  const options: huks.HuksOptions = ceremonyOptions(nonce, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, body, tag);
  let handle: huks.HuksSessionHandle | null = null;
  try {
    handle = await huks.initSession(SECRET_KEY_ALIAS, options);
    const result: huks.HuksReturnResult = await huks.finishSession(handle.handle, options);
    const plain: Uint8Array | undefined = result.outData;
    if (plain === undefined || plain.length === 0) {
      logW('[WebProxyVault] unseal produced no plaintext');
      return '';
    }
    return decodeText(plain);
  } catch (err) {
    logE('[WebProxyVault] unseal failed: ' + errorText(err));
    return '';
  }
}
