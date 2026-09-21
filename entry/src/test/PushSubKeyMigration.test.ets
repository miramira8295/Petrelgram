import { describe, it, expect } from '@ohos/hypium';
import { hmsSubKeyToAdopt } from '../main/ets/util/pushSubKeyMigration';

const HMS: string = 'hmskey0011223344556677889900aabbccddeeff00112233';
const MEOW: string = 'meowkey99887766554433221100ffeeddccbbaa9988776655';

export default function pushSubKeyMigrationTest() {
  describe('PushSubKeyMigration', () => {
    it('已经有自己的 key 就一直用它', 0, () => {
      expect(hmsSubKeyToAdopt(HMS, MEOW, true)).assertEqual(HMS);
      expect(hmsSubKeyToAdopt(HMS, MEOW, false)).assertEqual(HMS);
      expect(hmsSubKeyToAdopt(HMS, '', true)).assertEqual(HMS);
    });

    // 升级路径：老版本 HMS 借的就是 meowSubKey，而 Telegram 服务端记着的是那条
    // 订阅的 endpoint。换新 key 会让中转多一条、推送仍走旧的，两边永远对不上。
    it('注册过的老设备接手 meowSubKey', 0, () => {
      expect(hmsSubKeyToAdopt('', MEOW, true)).assertEqual(MEOW);
    });

    // 只用过 MeoW 的人也有 meowSubKey。接过来等于又把两条通道绑回一起，
    // 这次改动就白做了——所以判据是「HMS 确实注册过」，不是「有没有 meowSubKey」。
    it('没注册过 HMS 就不接手，去生成新的', 0, () => {
      expect(hmsSubKeyToAdopt('', MEOW, false)).assertEqual('');
    });

    it('两边都空一律生成新的', 0, () => {
      expect(hmsSubKeyToAdopt('', '', true)).assertEqual('');
      expect(hmsSubKeyToAdopt('', '', false)).assertEqual('');
    });

    it('空白串当空处理，不会把一串空格当成 key 发给中转', 0, () => {
      expect(hmsSubKeyToAdopt('   ', MEOW, true)).assertEqual(MEOW);
      expect(hmsSubKeyToAdopt('', '   ', true)).assertEqual('');
    });

    it('自己的 key 前后有空白时取整后返回', 0, () => {
      expect(hmsSubKeyToAdopt(`  ${HMS}  `, MEOW, true)).assertEqual(HMS);
    });

    // 幂等：接手一次之后 storedHmsSubKey 就非空了，再调返回同一把，
    // 不会每次启动都重新"接手"一遍。
    it('接手之后幂等', 0, () => {
      const first: string = hmsSubKeyToAdopt('', MEOW, true);
      expect(hmsSubKeyToAdopt(first, MEOW, true)).assertEqual(first);
    });
  });
}
