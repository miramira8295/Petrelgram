import { ChatKind } from './ChatEntry';
import { SCOPE_CHANNEL, SCOPE_GROUP, SCOPE_PRIVATE } from './NotificationApi';

// 分类默认静音（私聊 / 群组 / 频道）的进程内缓存。
//
// **为什么界面需要它。** TDLib 的 chatNotificationSettings 里，
// use_default_mute_for 为 true 时 mute_for 是**无意义的**（官方文档原话：
// "If true, mute_for is ignored and the value for the relevant type of chat is
// used instead"）。会话列表原来直接拿 mute_for > 0 当静音状态，于是
// "在通知设置里把频道整类静音" 这种最常见的用法，在我们这里一个铃铛都不画——
// 官版显示静音、我们显示没静音（issue #110）。
//
// NotificationService 早就有这套判断（它决定要不要弹通知），但那份状态藏在
// 服务实例里，界面拿不到。搬到这里之后两边共用一份，不会再出现"通知不弹、
// 列表却显示未静音"这种自相矛盾。
//
// 纪元（epoch）而不是订阅回调：分类设置一改，**所有**会话行的显示都可能变，
// 而会话行本来就按 key 重建。把纪元放进 key 里，一次写入带动全表刷新，和
// LANGUAGE_EPOCH 是同一套办法。
export const SCOPE_MUTE_EPOCH: string = 'scopeMuteEpoch';

// 读不到时按"未静音"。宁可把跟随默认的会话显示成会响，也好过反过来让用户
// 以为自己已经静音了——后者会让人错过消息。
const muted: Map<string, boolean> = new Map<string, boolean>();

// 会话类型 → 分类。密聊跟私聊走（TDLib 没有单独的密聊分类）。
export function scopeOfKind(kind: ChatKind): string {
  if (kind === 'channel') {
    return SCOPE_CHANNEL;
  }
  if (kind === 'supergroup' || kind === 'basicGroup') {
    return SCOPE_GROUP;
  }
  return SCOPE_PRIVATE;
}

export function scopeMuted(scope: string): boolean {
  return muted.get(scope) ?? false;
}

export function scopeMutedForKind(kind: ChatKind): boolean {
  return scopeMuted(scopeOfKind(kind));
}

// 写入一个分类的值。同值不动——纪元每加一次就是一次全表重建，白刷不得。
export function setScopeMuted(scope: string, value: boolean): void {
  if (muted.get(scope) === value) {
    return;
  }
  muted.set(scope, value);
  AppStorage.setOrCreate<number>(SCOPE_MUTE_EPOCH,
    (AppStorage.get<number>(SCOPE_MUTE_EPOCH) ?? 0) + 1);
}

// updateScopeNotificationSettings 的 scope['@type'] → 我们的分类名。
// 认不出来的返回空串，调用方据此忽略——TDLib 后续版本加新分类时不该让我们
// 把它错当成私聊。
export function scopeOfTdType(typeName: string): string {
  if (typeName === 'notificationSettingsScopeGroupChats') {
    return SCOPE_GROUP;
  }
  if (typeName === 'notificationSettingsScopeChannelChats') {
    return SCOPE_CHANNEL;
  }
  if (typeName === 'notificationSettingsScopePrivateChats') {
    return SCOPE_PRIVATE;
  }
  return '';
}

// 换账号时必须清空：上一个账号把频道整类静音了，新账号没有，留着就是错的。
export function resetScopeMute(): void {
  muted.clear();
  AppStorage.setOrCreate<number>(SCOPE_MUTE_EPOCH,
    (AppStorage.get<number>(SCOPE_MUTE_EPOCH) ?? 0) + 1);
}
