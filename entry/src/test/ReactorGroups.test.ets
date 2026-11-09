import { describe, expect, it } from '@ohos/hypium';
import { ReactorGroup, ReactorRow, groupReactors } from '../main/ets/util/reactorGroups';

function row(key: string, name: string): ReactorRow {
  return { reactionKey: key, userId: 0, chatId: 0, name: name };
}

export default function reactorGroupsTest() {
  describe('reactorGroups', () => {
    // 点表情条末尾的「>」弹出的名单：按表情分组，组内保持服务端给的顺序（最新在前）。
    it('按表情分组，组的先后按第一次出现的顺序', 0, () => {
      const groups: ReactorGroup[] = groupReactors([
        row('❤', 'aaa'), row('👍', 'djdoq'), row('❤', 'bbbb'), row('❤', 'ccc'), row('👍', 'jdasjod')
      ]);
      expect(groups.length).assertEqual(2);
      expect(groups[0].reactionKey).assertEqual('❤');
      expect(groups[0].rows.map((r: ReactorRow): string => r.name).join(',')).assertEqual('aaa,bbbb,ccc');
      expect(groups[1].reactionKey).assertEqual('👍');
      expect(groups[1].rows.map((r: ReactorRow): string => r.name).join(',')).assertEqual('djdoq,jdasjod');
    });

    it('没有人就是空列表', 0, () => {
      expect(groupReactors([]).length).assertEqual(0);
    });

    it('认不出表情的行不丢，归到空键那一组', 0, () => {
      const groups: ReactorGroup[] = groupReactors([row('', 'x')]);
      expect(groups.length).assertEqual(1);
      expect(groups[0].rows.length).assertEqual(1);
    });
  });
}
