import { describe, expect, it } from '@ohos/hypium';
import {
  resetScopeMute, scopeMuted, scopeMutedForKind, scopeOfKind, scopeOfTdType, setScopeMuted
} from '../main/ets/store/ScopeMuteStore';
import { SCOPE_CHANNEL, SCOPE_GROUP, SCOPE_PRIVATE } from '../main/ets/store/NotificationApi';

export default function scopeMuteTest() {
  describe('scopeMute', () => {
    it('会话类型落到正确的分类', 0, (): void => {
      expect(scopeOfKind('channel')).assertEqual(SCOPE_CHANNEL);
      expect(scopeOfKind('supergroup')).assertEqual(SCOPE_GROUP);
      expect(scopeOfKind('basicGroup')).assertEqual(SCOPE_GROUP);
      expect(scopeOfKind('private')).assertEqual(SCOPE_PRIVATE);
      // 密聊跟私聊走——TDLib 没有单独的密聊通知分类。
      expect(scopeOfKind('secret')).assertEqual(SCOPE_PRIVATE);
    });

    it('TDLib 的 scope 类型名映射得上', 0, (): void => {
      expect(scopeOfTdType('notificationSettingsScopeGroupChats')).assertEqual(SCOPE_GROUP);
      expect(scopeOfTdType('notificationSettingsScopeChannelChats')).assertEqual(SCOPE_CHANNEL);
      expect(scopeOfTdType('notificationSettingsScopePrivateChats')).assertEqual(SCOPE_PRIVATE);
    });

    it('认不出的分类返回空串，不当成私聊', 0, (): void => {
      // TDLib 后续版本若加了新分类，把它错当私聊会让一整类会话的静音状态显示反。
      expect(scopeOfTdType('notificationSettingsScopeSomethingNew')).assertEqual('');
      expect(scopeOfTdType('')).assertEqual('');
    });

    it('没读到的分类按未静音', 0, (): void => {
      // 宁可把跟随默认的会话显示成会响，也好过反过来让用户以为已经静音——
      // 后者会让人错过消息。
      resetScopeMute();
      expect(scopeMuted(SCOPE_CHANNEL)).assertFalse();
      expect(scopeMutedForKind('channel')).assertFalse();
    });

    it('写入后按类型读得到，互不串台', 0, (): void => {
      resetScopeMute();
      setScopeMuted(SCOPE_CHANNEL, true);
      expect(scopeMutedForKind('channel')).assertTrue();
      expect(scopeMutedForKind('supergroup')).assertFalse();
      expect(scopeMutedForKind('private')).assertFalse();
    });

    it('换账号后清空', 0, (): void => {
      // 上一个账号把频道整类静音了，新账号未必。缓存住在模块级 Map 里，不随
      // 运行时销毁而消失，必须显式清。
      resetScopeMute();
      setScopeMuted(SCOPE_GROUP, true);
      expect(scopeMutedForKind('supergroup')).assertTrue();
      resetScopeMute();
      expect(scopeMutedForKind('supergroup')).assertFalse();
    });

    it('同值写入不推进纪元', 0, (): void => {
      // 纪元每加一次就是一次全表重建。
      resetScopeMute();
      setScopeMuted(SCOPE_GROUP, true);
      const after: number = AppStorage.get<number>('scopeMuteEpoch') ?? 0;
      setScopeMuted(SCOPE_GROUP, true);
      expect(AppStorage.get<number>('scopeMuteEpoch') ?? 0).assertEqual(after);
      setScopeMuted(SCOPE_GROUP, false);
      expect((AppStorage.get<number>('scopeMuteEpoch') ?? 0) > after).assertTrue();
    });
  });
}
