import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { messageDeletableFromProperties } from './messageModeration';
import { logE } from './log';

// 「这条消息能不能删」的缓存，供消息菜单决定要不要出「删除」那一项。
//
// 和 util/messageEditable 是同一套形状、同一个理由（那边文件头有完整论证）：
// 判据不在原始 message 上——同一族的 can_be_forwarded / can_be_saved 在
// services/MessageDragSource 里也是白拿着整条 message、额外发一次查询拿的——
// 只能问 getMessageProperties。菜单是同步构建的，答案来不及就先**按能删显示**，
// 到货之后菜单自己重绘。
//
// 唯一和编辑那边不同的是默认方向：编辑未知时退回"自己发的且 48 小时内"这条
// 启发式；这里未知时一律当能删，最坏情况等于没这个模块——用户点了才发现删
// 不了，和修之前一模一样。理由见 messageDeletableFromProperties 的三态说明。

// messageId 只在会话内唯一，所以这份缓存和 editable 的一样是**会话作用域**：
// 换会话必须 clearDeletableCache()，否则会把上一个会话的判断带过来。
const cache: Map<number, boolean> = new Map();
// 在途去重：菜单重建会再问一遍，别叠着发。
const inFlight: Set<number> = new Set();

// undefined = 还不知道。调用方据此决定"维持现状"。
export function deletableCached(messageId: number): boolean | undefined {
  return cache.get(messageId);
}

export function clearDeletableCache(): void {
  cache.clear();
  inFlight.clear();
}

// 供单测用：喂一个已知答案进去，不碰 TDLib。
export function seedDeletableForTest(messageId: number, deletable: boolean): void {
  cache.set(messageId, deletable);
}

// 问一次并缓存。已经知道答案、或正在问的，直接返回不重复发。
// onResolved 只在**这一次真的拿到确定答案**时回调，调用方据此触发重绘。
export function ensureDeletable(client: TdClient, chatId: number, messageId: number,
  onResolved: (deletable: boolean) => void): void {
  if (chatId === 0 || messageId <= 0) {
    return;
  }
  if (cache.has(messageId) || inFlight.has(messageId)) {
    return;
  }
  inFlight.add(messageId);
  const req: TdRequest = { '@type': 'getMessageProperties' };
  req['chat_id'] = chatId;
  req['message_id'] = messageId;
  client.send(req, 10000).then((properties: TdObject): void => {
    inFlight.delete(messageId);
    const deletable: boolean | undefined = messageDeletableFromProperties(properties);
    // 认不出来就不缓存，也不回调：一次异常返回不该把这条消息永久定性。
    // 不缓存的话下次开菜单会再问一次。
    if (deletable === undefined) {
      return;
    }
    cache.set(messageId, deletable);
    onResolved(deletable);
  }).catch((e: TdError): void => {
    inFlight.delete(messageId);
    // 和 editable 一样：失败不缓存 false，否则一次网络抖动会把「删除」
    // 永久藏起来，比现状更糟。
    logE(`messageDeletable(${messageId}) failed: ${e.message}`);
  });
}
