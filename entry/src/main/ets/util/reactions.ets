import { str } from './strings';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../tdkit/Globals';
import { logE } from './log';

// 反应在 UI 层（气泡 chip、面板、长按详情）统一用一个字符串 key 传递：
// 标准反应就是 emoji 本身，自定义 emoji 反应加 'ce:' 前缀。这样既有的
// string 通道不必全部改成对象签名，而 Unicode emoji 不可能以 ASCII 前缀
// 开头，两类 key 不会相撞。
const CUSTOM_EMOJI_KEY_PREFIX: string = 'ce:';

export interface ReactionKey {
  emoji: string;         // 标准 emoji（自定义反应为 ''）
  customEmojiId: string; // 自定义 emoji id，int64 以字符串承载（标准反应为 ''）
}

// getMessageAvailableReactions 的解析结果：面板需要的三样东西。
export interface AvailableReactionSet {
  emojis: string[];         // 标准 emoji 反应，按 top/recent/popular 顺序去重
  customEmojiIds: string[]; // 自定义 emoji 反应 id，同样去重
  allowCustomEmoji: boolean;// 服务端是否允许该消息使用自定义 emoji 反应
}

export function customEmojiReactionKey(customEmojiId: string): string {
  return customEmojiId === '' ? '' : `${CUSTOM_EMOJI_KEY_PREFIX}${customEmojiId}`;
}

// 气泡上的 ReactionInfo 只带两个原始字段，这里给出统一的 key 拼装入口，
// 避免每个调用点各自判断该用 emoji 还是 id。
export function reactionKeyFrom(emoji: string, customEmojiId: string): string {
  return customEmojiId !== '' ? customEmojiReactionKey(customEmojiId) : emoji;
}

export function isCustomEmojiReactionKey(key: string): boolean {
  return key.startsWith(CUSTOM_EMOJI_KEY_PREFIX) &&
    key.length > CUSTOM_EMOJI_KEY_PREFIX.length;
}

export function parseReactionKey(key: string): ReactionKey {
  if (isCustomEmojiReactionKey(key)) {
    return { emoji: '', customEmojiId: key.substring(CUSTOM_EMOJI_KEY_PREFIX.length) };
  }
  return { emoji: key, customEmojiId: '' };
}

// 构造 addMessageReaction / removeMessageReaction / getMessageAddedReactions
// 需要的 ReactionType。custom_emoji_id 是 int64，TDLib 的 JSON 约定用字符串
// 传递，这里保持字符串原样，绝不能转成 number（超过 2^53 会丢精度）。
export function reactionTypeOf(key: string): TdObject {
  const parsed: ReactionKey = parseReactionKey(key);
  if (parsed.customEmojiId !== '') {
    const custom: TdObject = { '@type': 'reactionTypeCustomEmoji' };
    custom['custom_emoji_id'] = parsed.customEmojiId;
    return custom;
  }
  const standard: TdObject = { '@type': 'reactionTypeEmoji' };
  standard['emoji'] = parsed.emoji;
  return standard;
}

// 长按 chip 的详情弹窗标题：自定义 emoji 没有可显示的字符，退化成文字说明。
export function reactionDisplayLabel(key: string): string {
  const parsed: ReactionKey = parseReactionKey(key);
  return parsed.customEmojiId !== '' ? str('reactions_custom_emoji') : parsed.emoji;
}

export function parseAvailableReactions(result: TdObject): AvailableReactionSet {
  const emojis: string[] = [];
  const customEmojiIds: string[] = [];
  const buckets: string[] = ['top_reactions', 'recent_reactions', 'popular_reactions'];
  for (const bucket of buckets) {
    for (const item of (result[bucket] as TdObject[] | undefined) ?? []) {
      const type = item['type'] as TdObject | undefined;
      if (type === undefined) {
        continue;
      }
      const typeName: string = (type['@type'] as string | undefined) ?? '';
      if (typeName === 'reactionTypeEmoji') {
        const emoji: string = (type['emoji'] as string | undefined) ?? '';
        if (emoji !== '' && emojis.indexOf(emoji) < 0) {
          emojis.push(emoji);
        }
      } else if (typeName === 'reactionTypeCustomEmoji') {
        const raw = type['custom_emoji_id'];
        const id: string = raw !== undefined ? `${raw}` : '';
        if (id !== '' && id !== '0' && customEmojiIds.indexOf(id) < 0) {
          customEmojiIds.push(id);
        }
      }
    }
  }
  return {
    emojis,
    customEmojiIds,
    allowCustomEmoji: (result['allow_custom_emoji'] as boolean | undefined) ?? false
  };
}

// 设为默认反应（长按反应面板里的某个 emoji）。不碰任何页面状态，之前被关在
// ChatPage 里；成功与失败都只是一句提示。
export function setDefaultReaction(emoji: string): void {
  const rt: TdObject = { '@type': 'reactionTypeEmoji' };
  rt['emoji'] = emoji;
  const req: TdRequest = { '@type': 'setDefaultReactionType' };
  req['reaction_type'] = rt;
  getTdClient().send(req).then((): void => {
    promptAction.showToast({ message: str('cp_default_reaction_set', emoji), duration: 1600 });
  }).catch((e: TdError): void => {
    logE(`setDefaultReaction failed: ${e.message}`);
    promptAction.showToast({ message: $r('app.string.cp_default_reaction_failed'), duration: 1600 });
  });
}
