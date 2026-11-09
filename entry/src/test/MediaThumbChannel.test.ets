import { describe, it, expect } from '@ohos/hypium';
import {
  publishThumbPath, thumbPathFor, subscribeThumbPath
} from '../main/ets/util/mediaThumbChannel';

export default function mediaThumbChannelTest() {
  describe('mediaThumbChannel', () => {
    it('未发布过的 fileId 读到空串', 0, () => {
      expect(thumbPathFor(900001)).assertEqual('');
    });

    it('发布后能读到，订阅者收到通知', 0, () => {
      const seen: string[] = [];
      const unsub = subscribeThumbPath(900002, (path: string): void => { seen.push(path); });
      publishThumbPath(900002, '/data/a.jpg');
      expect(thumbPathFor(900002)).assertEqual('/data/a.jpg');
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual('/data/a.jpg');
      unsub();
    });

    it('空路径不发布——避免把"还没下好"当成一次更新', 0, () => {
      const seen: string[] = [];
      const unsub = subscribeThumbPath(900003, (path: string): void => { seen.push(path); });
      publishThumbPath(900003, '');
      expect(thumbPathFor(900003)).assertEqual('');
      expect(seen.length).assertEqual(0);
      unsub();
    });

    it('重复发布同一路径不再通知', 0, () => {
      const seen: string[] = [];
      const unsub = subscribeThumbPath(900004, (path: string): void => { seen.push(path); });
      publishThumbPath(900004, '/data/b.jpg');
      publishThumbPath(900004, '/data/b.jpg');
      expect(seen.length).assertEqual(1);
      unsub();
    });

    it('路径变化会再次通知', 0, () => {
      const seen: string[] = [];
      const unsub = subscribeThumbPath(900005, (path: string): void => { seen.push(path); });
      publishThumbPath(900005, '/data/c1.jpg');
      publishThumbPath(900005, '/data/c2.jpg');
      expect(seen.length).assertEqual(2);
      expect(seen[1]).assertEqual('/data/c2.jpg');
      unsub();
    });

    it('退订后不再收到通知', 0, () => {
      const seen: string[] = [];
      const unsub = subscribeThumbPath(900006, (path: string): void => { seen.push(path); });
      unsub();
      publishThumbPath(900006, '/data/d.jpg');
      expect(seen.length).assertEqual(0);
      expect(thumbPathFor(900006)).assertEqual('/data/d.jpg');
    });

    it('同一 fileId 的多个订阅者都收到', 0, () => {
      let a: number = 0;
      let b: number = 0;
      const unsubA = subscribeThumbPath(900007, (): void => { a++; });
      const unsubB = subscribeThumbPath(900007, (): void => { b++; });
      publishThumbPath(900007, '/data/e.jpg');
      expect(a).assertEqual(1);
      expect(b).assertEqual(1);
      unsubA();
      unsubB();
    });

    it('订阅者之间互不影响：一个退订不影响另一个', 0, () => {
      let a: number = 0;
      let b: number = 0;
      const unsubA = subscribeThumbPath(900008, (): void => { a++; });
      const unsubB = subscribeThumbPath(900008, (): void => { b++; });
      unsubA();
      publishThumbPath(900008, '/data/f.jpg');
      expect(a).assertEqual(0);
      expect(b).assertEqual(1);
      unsubB();
    });
  });
}
