import { describe, expect, it } from '@ohos/hypium';
import { JoinNoticeInput, isRealClientJoinNotice } from '../main/ets/util/joinNotice';

function msg(
  contentType: string, isOutgoing: boolean, placeholderLabel: string, systemType: string
): JoinNoticeInput {
  return { contentType: contentType, isOutgoing: isOutgoing,
    placeholderLabel: placeholderLabel, systemType: systemType };
}

// 宿主单测里 str() 原样返回 key，所以文案比较那两支等价于比对 key 本身。
export default function joinNoticeTest() {
  describe('joinNotice', () => {
    it('必须是自己发出的系统消息', 0, () => {
      // 别人入群的提示不算——否则群里每来一个人都会压掉本地提示。
      expect(isRealClientJoinNotice(msg('system', false, 'cp_joined_group', ''))).assertFalse();
      // 普通文本消息即便文案撞上也不算。
      expect(isRealClientJoinNotice(msg('text', true, 'cp_joined_group', ''))).assertFalse();
    });

    it('systemType 是可靠的那两个判据', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByLink'))).assertTrue();
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByRequest'))).assertTrue();
    });

    it('文案判据：群与频道各一条', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_group', ''))).assertTrue();
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_channel', ''))).assertTrue();
    });

    it('文案对不上且 systemType 也不匹配时为假', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, '别的系统提示', 'messageChatChangeTitle')))
        .assertFalse();
      expect(isRealClientJoinNotice(msg('system', true, '', ''))).assertFalse();
    });

    it('四个判据是或的关系，任一命中即可', 0, () => {
      // 文案空但 systemType 命中。
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByLink'))).assertTrue();
      // systemType 是别的但文案命中。
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_group', 'messageChatAddMembers')))
        .assertTrue();
    });
  });
}
