import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { fileNameFromUri } from '../util/mediaPick';
import {
  SharedItem, SharedPayload, SharedRecordLike,
  ancestorCandidates, itemOf, splitPayload
} from '../util/sharedContent';
import { logE, logI } from '../util/log';

// 别的应用分享进来的东西，从 want 一路到"可以发送的载荷"。
//
// 【为什么要把文件复制进沙箱】分享方给的是临时授权的 URI，授权跟着**接收它的
// 那个进程**走。两条路都需要复制：
//   · 分享面板里那个扩展进程只负责"选人"，真正发送在主应用进程里 —— URI 授权
//     不会跟着 want 传过去，不复制的话主应用打开就是一个读不了的路径；
//   · 就算是直接拉起主应用这条路，授权也可能在用户还在挑会话时就过期了。
// 复制到 cacheDir 之后，后面的发送链和"从相册选图"走的是同一条路。

// 一次分享最多收几条。系统侧本来就有 500 条上限，我们再收一道——
// 一次发几十个文件不是正常用法，而每一条都要复制一遍磁盘。
const MAX_RECORDS: number = 20;

// 待处理的分享。主应用取走之前一直放在这里。
let pending: SharedPayload | null = null;

export function takePendingShare(): SharedPayload | null {
  const payload: SharedPayload | null = pending;
  pending = null;
  return payload;
}

export function hasPendingShare(): boolean {
  return pending !== null;
}

// 只看不取。选择器要用它渲染"分享了什么"的那行摘要，而载荷得留到用户
// 真的选好会话之后再由 ChatPage 取走。
export function peekPendingShare(): SharedPayload | null {
  return pending;
}

// --- 「目标会话已经开着」这条旁路 ----------------------------------------
//
// 正常路径是路由参数 sharePending，会话页在应用路由参数时取走载荷。但
// util/splitRouting 的 decideChatPush 有一支 `action: 'skip'`：目标会话已经
// 在栈顶时**什么都不做**，路由参数根本不会被重新应用——分享就静默丢了。
// （复现：会话 X 开着 → 切到图库 → 分享给 Petrelgram → 选 X → 没反应。）
//
// 所以再开一条：选好目标时广播一次 chatId，开着的会话页认领自己那一条。
// 两条路都靠 takePendingShare 的**取走**语义防重复，谁先到谁生效。

const targetListeners: Set<(chatId: number) => void> = new Set<(chatId: number) => void>();

export function onShareTargeted(listener: (chatId: number) => void): () => void {
  targetListeners.add(listener);
  return (): void => {
    targetListeners.delete(listener);
  };
}

export function notifyShareTargeted(chatId: number): void {
  targetListeners.forEach((listener: (chatId: number) => void): void => listener(chatId));
}

export function stashPendingShare(payload: SharedPayload): void {
  pending = payload;
}

// 这个 want 是不是"别人分享东西给我们"。
export function isShareWant(want: Want): boolean {
  return (want.action ?? '') === 'ohos.want.action.sendData';
}

// 把 UTD 归化到我们认识的中间类型。认不出来返回空串，分类器自己会退化。
// getTypeDescriptor 对未注册的类型会抛，所以整段包起来。
function ancestorOf(typeId: string): string {
  if (typeId === '') {
    return '';
  }
  try {
    const descriptor: utd.TypeDescriptor = utd.getTypeDescriptor(typeId);
    const candidates: string[] = ancestorCandidates();
    for (let i = 0; i < candidates.length; i++) {
      if (descriptor.belongsTo(candidates[i])) {
        return candidates[i];
      }
    }
  } catch (e) {
    // 未注册的自定义类型走这里，属于正常情况，不当错误记。
  }
  return '';
}

// 目的地路径。带上一个序号防止同一毫秒内多条撞名。
function inboxDest(cacheDir: string, uri: string, seq: number): string {
  return `${cacheDir}/share_${Date.now()}_${seq}_${fileNameFromUri(uri)}`;
}

// 把一个 URI 复制进沙箱，返回新路径；失败返回空串（调用方丢弃这一条，
// 不让一条读不了的文件毁掉整次分享）。
function copyIntoSandbox(cacheDir: string, uri: string, seq: number): string {
  let src: fs.File | null = null;
  try {
    const dest: string = inboxDest(cacheDir, uri, seq);
    src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    fs.copyFileSync(src.fd, dest);
    return dest;
  } catch (e) {
    logE(`ShareInbox.copy failed for ${uri}: ${e}`);
    return '';
  } finally {
    if (src !== null) {
      fs.closeSync(src);
    }
  }
}

// SharedData → 我们的载荷。文件在这一步就复制进沙箱。
function payloadOf(data: systemShare.SharedData, cacheDir: string): SharedPayload {
  const records: systemShare.SharedRecord[] = data.getRecords();
  const items: SharedItem[] = [];
  const limit: number = Math.min(records.length, MAX_RECORDS);
  for (let i = 0; i < limit; i++) {
    const record: systemShare.SharedRecord = records[i];
    const like: SharedRecordLike = {
      utd: record.utd ?? '',
      uri: record.uri,
      content: record.content,
      title: record.title
    };
    logI(`[Share] record ${i}: utd=${like.utd} hasUri=${(like.uri ?? '') !== ''}`);
    const item: SharedItem | null = itemOf(like, ancestorOf(like.utd));
    if (item === null) {
      continue;
    }
    if (item.uri === '') {
      items.push(item);
      continue;
    }
    const local: string = copyIntoSandbox(cacheDir, item.uri, i);
    if (local === '') {
      continue;
    }
    // sourceUri 保留分享方给的原始 URI：实况照片要靠它去媒体库取动态部分
    // （见 util/shareLivePhoto）。
    items.push({
      kind: item.kind, uri: local, text: '', title: item.title, sourceUri: item.sourceUri
    });
  }
  if (records.length > limit) {
    logI(`[Share] ${records.length} records, taking first ${limit}`);
  }
  return splitPayload(items);
}

// 从 want 解析出载荷。解析失败/为空时返回 null——调用方据此当作"不是分享"。
export function parseShareWant(want: Want, cacheDir: string): Promise<SharedPayload | null> {
  return systemShare.getSharedData(want).then(
    (data: systemShare.SharedData): SharedPayload | null => {
      const payload: SharedPayload = payloadOf(data, cacheDir);
      if (payload.caption === '' && payload.media.length === 0) {
        return null;
      }
      logI(`[Share] received caption=${payload.caption.length}ch media=${payload.media.length}`);
      return payload;
    }).catch((e: Object): SharedPayload | null => {
      logE(`ShareInbox.parseShareWant failed: ${e}`);
      return null;
    });
}

// 意图框架推荐的联系人。用户从分享面板上直接点某个头像时，系统会把那个
// 联系人的 entityId 放进 want——那正是我们捐献时写进去的 chatId。
// 拿不到就返回 0，走"进应用自己挑"的路。
export function contactChatIdOf(want: Want): Promise<number> {
  return systemShare.getContactInfo(want).then(
    (info: systemShare.ContactInfo): number => {
      const id: number = Number.parseInt(info.contactId ?? '', 10);
      return Number.isNaN(id) ? 0 : id;
    }).catch((): number => 0);
}
