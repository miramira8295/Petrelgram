import { describe, expect, it } from '@ohos/hypium';
import { badgeLabel, folderBadge, setFolderBadge } from '../main/ets/util/folderBadges';

export default function folderBadgesTest() {
  describe('folderBadges', () => {
    it('同一 key 拿到同一实例（@ObjectLink 靠对象身份存活）', 0, (): void => {
      const a = folderBadge('folder:identity');
      const b = folderBadge('folder:identity');
      expect(a === b).assertTrue();
      expect(folderBadge('folder:other') === a).assertFalse();
    });
    it('setFolderBadge 写入并保持实例不换', 0, (): void => {
      const badge = folderBadge('folder:set');
      setFolderBadge('folder:set', 7, true);
      expect(badge.count).assertEqual(7);
      expect(badge.hasUnmuted).assertTrue();
      expect(folderBadge('folder:set') === badge).assertTrue();
      setFolderBadge('folder:set', 0);
      expect(badge.count).assertEqual(0);
    });
    it('角标文案 99+ 截断', 0, (): void => {
      expect(badgeLabel(0, 99)).assertEqual('0');
      expect(badgeLabel(99, 99)).assertEqual('99');
      expect(badgeLabel(100, 99)).assertEqual('99+');
      expect(badgeLabel(1, 99)).assertEqual('1');
    });

    // issue #155：数全部未读会话，颜色由"有没有未静音的"决定。全静音 → 灰。
    it('hasUnmuted 跟着写入，全静音时为 false', 0, (): void => {
      const badge = folderBadge('folder:muted-only');
      setFolderBadge('folder:muted-only', 4, false);
      expect(badge.count).assertEqual(4);
      expect(badge.hasUnmuted).assertFalse();
      setFolderBadge('folder:muted-only', 4, true);
      expect(badge.hasUnmuted).assertTrue();
    });
  });
}
