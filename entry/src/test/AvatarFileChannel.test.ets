import { describe, it, expect } from '@ohos/hypium';
import {
  avatarFilePathFor, publishAvatarFile, resetAvatarFileChannelForTest, subscribeAvatarFile
} from '../main/ets/util/avatarFileChannel';

export default function avatarFileChannelTest() {
  describe('AvatarFileChannel', () => {
    it('发布之后能取到现值', 0, () => {
      resetAvatarFileChannelForTest();
      expect(avatarFilePathFor(7)).assertEqual('');
      publishAvatarFile(7, '/a/7.jpg');
      expect(avatarFilePathFor(7)).assertEqual('/a/7.jpg');
    });

    it('订阅者收到推送', 0, () => {
      resetAvatarFileChannelForTest();
      let got: string = '';
      subscribeAvatarFile(9, (p: string): void => { got = p; });
      publishAvatarFile(9, '/a/9.jpg');
      expect(got).assertEqual('/a/9.jpg');
    });

    // 空路径代表"还没下好"，不是一次内容更新——发出去会让订阅方把已有的图清掉。
    it('空路径不发布、不改现值', 0, () => {
      resetAvatarFileChannelForTest();
      publishAvatarFile(3, '/a/3.jpg');
      let hits: number = 0;
      subscribeAvatarFile(3, (): void => { hits++; });
      publishAvatarFile(3, '');
      expect(avatarFilePathFor(3)).assertEqual('/a/3.jpg');
      expect(hits).assertEqual(0);
    });

    // 每条 updateFile 都会走到这里，路径没变就不该把订阅者叫醒一遍。
    it('路径没变不通知', 0, () => {
      resetAvatarFileChannelForTest();
      publishAvatarFile(4, '/a/4.jpg');
      let hits: number = 0;
      subscribeAvatarFile(4, (): void => { hits++; });
      publishAvatarFile(4, '/a/4.jpg');
      expect(hits).assertEqual(0);
      publishAvatarFile(4, '/a/4b.jpg');
      expect(hits).assertEqual(1);
    });

    it('fileId 为 0 一律忽略（0 = 没有头像）', 0, () => {
      resetAvatarFileChannelForTest();
      let hits: number = 0;
      subscribeAvatarFile(0, (): void => { hits++; });
      publishAvatarFile(0, '/a/0.jpg');
      expect(avatarFilePathFor(0)).assertEqual('');
      expect(hits).assertEqual(0);
    });

    // 不退订会让回调一直持有组件实例（官方 FAQ 点过的泄漏），而 @ 弹窗每敲一个
    // 字符就可能整列重建。
    it('退订之后不再收到', 0, () => {
      resetAvatarFileChannelForTest();
      let hits: number = 0;
      const off: () => void = subscribeAvatarFile(5, (): void => { hits++; });
      publishAvatarFile(5, '/a/5.jpg');
      off();
      publishAvatarFile(5, '/a/5b.jpg');
      expect(hits).assertEqual(1);
    });

    it('同一个 id 多个订阅者都收到，互不影响', 0, () => {
      resetAvatarFileChannelForTest();
      let a: number = 0;
      let b: number = 0;
      const offA: () => void = subscribeAvatarFile(6, (): void => { a++; });
      subscribeAvatarFile(6, (): void => { b++; });
      publishAvatarFile(6, '/a/6.jpg');
      offA();
      publishAvatarFile(6, '/a/6b.jpg');
      expect(a).assertEqual(1);
      expect(b).assertEqual(2);
    });

    it('不同 id 互不串台', 0, () => {
      resetAvatarFileChannelForTest();
      let hits: number = 0;
      subscribeAvatarFile(1, (): void => { hits++; });
      publishAvatarFile(2, '/a/2.jpg');
      expect(hits).assertEqual(0);
      expect(avatarFilePathFor(1)).assertEqual('');
    });
  });
}
