import { describe, expect, it } from '@ohos/hypium';
import {
  CompiledChatFilter, FilterableMessage, MAX_FILTER_AUTO_BACKFILL, MessageFilterConfig,
  compileFilterForChat, messageMatchesFilter, normalizeUsernamePattern,
  parseMessageFilterConfig, serializeMessageFilterConfig, shouldAutoBackfillFilteredPage,
  validateFilterPattern
} from '../main/ets/util/messageFilter';

function sampleMsg(
  senderUserId: number, senderName: string, senderUsernames: string[],
  text: string, caption: string = '', isOutgoing: boolean = false, isService: boolean = false
): FilterableMessage {
  return {
    isOutgoing,
    isService,
    senderUserId,
    senderName,
    senderUsernames,
    text,
    caption,
    forwardFrom: '',
    linkPreviewTitle: ''
  };
}

export default function messageFilterTest(): void {
  describe('messageFilter', (): void => {
    it('用户名规范化与正则校验', 0, (): void => {
      expect(normalizeUsernamePattern(' @SpamBot ')).assertEqual('spambot');
      expect(normalizeUsernamePattern('Alice_01')).assertEqual('alice_01');
      expect(validateFilterPattern('keyword', 'contains', '广告')).assertTrue();
      expect(validateFilterPattern('keyword', 'regex', '优惠[0-9]+')).assertTrue();
      expect(validateFilterPattern('keyword', 'regex', '[未闭合正则')).assertFalse();
      expect(validateFilterPattern('user', 'exact', '@')).assertFalse();
    });

    it('按用户名 / userId / 昵称 / 关键字拦截，且永不拦截自己与服务消息', 0, (): void => {
      const cfg: MessageFilterConfig = {
        enabled: true,
        disabledGlobalChatIds: [],
        rules: [
          { id: '1', enabled: true, chatId: 0, field: 'user', mode: 'exact', pattern: '@ad_bot', userId: 9001 },
          { id: '2', enabled: true, chatId: 0, field: 'nickname', mode: 'contains', pattern: '代购' },
          { id: '3', enabled: true, chatId: -1001, field: 'keyword', mode: 'contains', pattern: '加微信' },
          { id: '4', enabled: true, chatId: -1001, field: 'keyword', mode: 'regex', pattern: '返利\\d+元' }
        ]
      };
      const compiled: CompiledChatFilter | null = compileFilterForChat(cfg, -1001);
      expect(compiled !== null).assertTrue();
      expect(messageMatchesFilter(sampleMsg(9001, '普通人', [], 'hi'), compiled)).assertTrue();
      expect(messageMatchesFilter(sampleMsg(123, '普通人', ['AD_Bot'], 'hi'), compiled)).assertTrue();
      expect(messageMatchesFilter(sampleMsg(124, '日本代购小王', [], '你好'), compiled)).assertTrue();
      expect(messageMatchesFilter(sampleMsg(125, '路人', [], '详情请加微信了解'), compiled)).assertTrue();
      expect(messageMatchesFilter(sampleMsg(126, '路人', [], '', '下单返利50元'), compiled)).assertTrue();
      expect(messageMatchesFilter(sampleMsg(127, '路人', [], '正常讨论技术'), compiled)).assertFalse();
      // 自己发的消息与系统服务消息永不拦截
      expect(messageMatchesFilter(sampleMsg(9001, '代购', ['ad_bot'], '加微信', '', true, false), compiled)).assertFalse();
      expect(messageMatchesFilter(sampleMsg(9001, '代购', ['ad_bot'], '加微信', '', false, true), compiled)).assertFalse();
    });

    it('单群白名单停用全局规则与空规则 O(1) 返回 null', 0, (): void => {
      const cfg: MessageFilterConfig = {
        enabled: true,
        disabledGlobalChatIds: [-1002],
        rules: [
          { id: '1', enabled: true, chatId: 0, field: 'keyword', mode: 'contains', pattern: '广告' },
          { id: '2', enabled: true, chatId: -1003, field: 'keyword', mode: 'contains', pattern: '刷屏' }
        ]
      };
      expect(compileFilterForChat(cfg, -1002) === null).assertTrue();
      expect(compileFilterForChat(cfg, -1001) !== null).assertTrue();
      expect(compileFilterForChat({ enabled: false, disabledGlobalChatIds: [], rules: cfg.rules }, -1001) === null).assertTrue();
    });

    it('配置序列化往返与坏数据容错', 0, (): void => {
      const cfg: MessageFilterConfig = {
        enabled: true,
        disabledGlobalChatIds: [-10099],
        rules: [
          { id: 'r1', enabled: true, chatId: -1001, field: 'user', mode: 'exact', pattern: 'bot1', userId: 77, note: '广告机器人' }
        ]
      };
      const restored: MessageFilterConfig = parseMessageFilterConfig(serializeMessageFilterConfig(cfg));
      expect(restored.enabled).assertTrue();
      expect(restored.disabledGlobalChatIds.length).assertEqual(1);
      expect(restored.rules.length).assertEqual(1);
      expect(restored.rules[0].userId).assertEqual(77);
      expect(restored.rules[0].note).assertEqual('广告机器人');

      const bad: MessageFilterConfig = parseMessageFilterConfig('{bad json');
      expect(bad.rules.length).assertEqual(0);
    });

    it('整页被拦截时的自动补页上限保护', 0, (): void => {
      expect(shouldAutoBackfillFilteredPage(true, 30, 0, 0, true, 0)).assertTrue();
      expect(shouldAutoBackfillFilteredPage(true, 30, 10, 10, true, 0)).assertFalse();
      expect(shouldAutoBackfillFilteredPage(false, 30, 12, 0, true, 1)).assertTrue();
      expect(shouldAutoBackfillFilteredPage(false, 30, 12, 2, true, 1)).assertFalse();
      expect(shouldAutoBackfillFilteredPage(false, 30, 12, 0, true, MAX_FILTER_AUTO_BACKFILL)).assertFalse();
      expect(shouldAutoBackfillFilteredPage(false, 30, 12, 0, false, 0)).assertFalse();
    });
  });
}
