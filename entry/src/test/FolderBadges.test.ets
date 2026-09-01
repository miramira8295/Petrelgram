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
      setFolderBadge('folder:set', 7);
      expect(badge.count).assertEqual(7);
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
  });
}
