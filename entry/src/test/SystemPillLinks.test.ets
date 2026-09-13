import { describe, it, expect } from '@ohos/hypium';
import {
  linkNamesInLabel, pillSegments, systemPillDefaultUserId, NamedUser, PillSegment, SystemPillLink
} from '../main/ets/util/systemPillLinks';

// 系统消息药丸里的人名可点（issue #201 第 3 条）：名字落在人身上，
// 只有一个人时整颗药丸都是他，其余区域默认第一个人。

function person(userId: number, name: string): NamedUser {
  return { userId, name };
}

export default function systemPillLinksTest(): void {
  describe('systemPillLinks', (): void => {

    it('单人：名字在文案里的区间被找到', 0, (): void => {
      const links: SystemPillLink[] = linkNamesInLabel('stanco koi 加入了群组', [person(7, 'stanco koi')]);
      expect(links.length).assertEqual(1);
      expect(links[0].userId).assertEqual(7);
      expect(links[0].start).assertEqual(0);
      expect(links[0].end).assertEqual(10);
    });

    it('多人：邀请人与被邀请的每个人各占一段，按出现顺序排', 0, (): void => {
      const links: SystemPillLink[] = linkNamesInLabel('A 邀请了 B、C、D',
        [person(1, 'A'), person(2, 'B'), person(3, 'C'), person(4, 'D')]);
      expect(links.map((l: SystemPillLink): number => l.userId).join(',')).assertEqual('1,2,3,4');
      expect(links[1].start).assertEqual(6);
      expect(links[3].end).assertEqual(11);
    });

    it('重名：顺序向后找，两个同名的人各得各的区间', 0, (): void => {
      const links: SystemPillLink[] = linkNamesInLabel('Bob 邀请了 Bob', [person(1, 'Bob'), person(2, 'Bob')]);
      expect(links.length).assertEqual(2);
      expect(links[0].start).assertEqual(0);
      expect(links[1].start).assertEqual(8);
    });

    it('名字为空或文案里找不到的人跳过', 0, (): void => {
      const links: SystemPillLink[] = linkNamesInLabel('有人 邀请了新成员', [person(1, ''), person(2, 'Zed')]);
      expect(links.length).assertEqual(0);
    });

    it('默认落点 = 文案里最先出现的那个人；没有链接就是 0', 0, (): void => {
      const links: SystemPillLink[] = linkNamesInLabel('A 邀请了 B', [person(2, 'B'), person(1, 'A')]);
      expect(systemPillDefaultUserId(links)).assertEqual(1);
      expect(systemPillDefaultUserId([])).assertEqual(0);
    });

    it('切段：名字段带各自的人，其余段带默认人，拼回去等于原文', 0, (): void => {
      const label: string = 'A 邀请了 B、C';
      const links: SystemPillLink[] = linkNamesInLabel(label, [person(1, 'A'), person(2, 'B'), person(3, 'C')]);
      const segs: PillSegment[] = pillSegments(label, links);
      expect(segs.map((s: PillSegment): string => s.text).join('')).assertEqual(label);
      expect(segs.map((s: PillSegment): number => s.userId).join(',')).assertEqual('1,1,2,1,3');
      expect(segs.map((s: PillSegment): string => s.isName ? 'N' : '-').join('')).assertEqual('N-N-N');
    });
  });
}
