import { describe, it, expect } from '@ohos/hypium';
import { planAvatarWarm, initialAvatarPaths, AVATAR_WARM_MAX } from '../main/ets/util/avatarWarm';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import { MessageEntry } from '../main/ets/store/MessageEntry';

const none = (_p: string): boolean => false;

export default function avatarWarmTest() {
  describe('avatarWarm', () => {
    it('去重：同一个发送者在首屏出现多次也只解一次', 0, (): void => {
      const plan: string[] = planAvatarWarm(['/a.jpg', '/b.jpg', '/a.jpg'], none);
      expect(plan.length).assertEqual(2);
      expect(plan.join(',')).assertEqual('/a.jpg,/b.jpg');
    });

    it('跳过空路径和已经在缓存里的', 0, (): void => {
      const cached = (p: string): boolean => p === '/hot.jpg';
      const plan: string[] = planAvatarWarm(['', '/hot.jpg', '/cold.jpg'], cached);
      expect(plan.join(',')).assertEqual('/cold.jpg');
    });

    it('封顶：首屏可见就那么几行，多出来的是白花解码', 0, (): void => {
      const many: string[] = [];
      for (let i = 0; i < AVATAR_WARM_MAX + 5; i++) { many.push(`/p${i}.jpg`); }
      expect(planAvatarWarm(many, none).length).assertEqual(AVATAR_WARM_MAX);
      expect(planAvatarWarm(many, none, 3).length).assertEqual(3);
    });

    it('全在缓存里时什么都不做', 0, (): void => {
      expect(planAvatarWarm(['/a.jpg'], (_p: string): boolean => true).length).assertEqual(0);
    });

    it('首屏取样从锚点往两边交替，先要用户一眼看到的那几行', 0, (): void => {
      const groups: AlbumGroup[] = [];
      for (let i = 0; i < 10; i++) {
        const head: MessageEntry = { senderAvatarPath: `/p${i}.jpg` } as MessageEntry;
        groups.push({ head: head } as AlbumGroup);
      }
      const paths: string[] = initialAvatarPaths(groups, 5, 2);
      expect(paths.join(',')).assertEqual('/p5.jpg,/p4.jpg,/p6.jpg,/p3.jpg,/p7.jpg');
    });

    it('锚点越界时按最后一行兜底；空列表返回空', 0, (): void => {
      expect(initialAvatarPaths([], 0, 2).length).assertEqual(0);
      const head: MessageEntry = { senderAvatarPath: '/only.jpg' } as MessageEntry;
      const one: AlbumGroup[] = [{ head: head } as AlbumGroup];
      expect(initialAvatarPaths(one, 99, 2).join(',')).assertEqual('/only.jpg');
    });
  });
}
