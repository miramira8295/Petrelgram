import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  registerStack, stackOf, clearAllStacks, resetStacksForTest, snapshotOf,
  NavStackLike, NavPathInfoLike
} from '../main/ets/util/navStacks';
import { StackFrame } from '../main/ets/util/splitRouting';

class FakeStack implements NavStackLike {
  names: string[] = [];
  params: (Object | undefined)[] = [];
  cleared: number = 0;

  clear(animated?: boolean): void {
    this.cleared = this.cleared + 1;
    this.names = [];
    this.params = [];
  }
  popped: number = 0;

  pop(animated?: boolean): void {
    this.popped = this.popped + 1;
    this.names.pop();
    this.params.pop();
  }
  pushPath(info: NavPathInfoLike): void {
    this.names.push(info.name);
    this.params.push(info.param);
  }
  size(): number { return this.names.length; }
  getAllPathName(): string[] { return this.names; }
  getParamByIndex(index: number): Object | undefined {
    return index >= 0 && index < this.params.length ? this.params[index] : undefined;
  }
}

function idKey(name: string, param: Object | undefined): string {
  if (param === undefined) { return ''; }
  const bag = param as Record<string, Object>;
  const v = bag['id'] as number | undefined;
  return v === undefined ? '' : `${v}`;
}

export default function navStacksTest(): void {
  describe('navStacks', (): void => {

    beforeEach((): void => { resetStacksForTest(); });

    it('没注册过取到 undefined', 0, (): void => {
      expect(stackOf('chat') === undefined).assertTrue();
    });

    it('注册后能取回同一个对象', 0, (): void => {
      const s = new FakeStack();
      registerStack('chat', s);
      expect(stackOf('chat') === s).assertTrue();
    });

    it('三个 tab 各存各的，互不串', 0, (): void => {
      const a = new FakeStack();
      const b = new FakeStack();
      registerStack('chat', a);
      registerStack('settings', b);
      expect(stackOf('chat') === a).assertTrue();
      expect(stackOf('settings') === b).assertTrue();
      expect(stackOf('contacts') === undefined).assertTrue();
    });

    it('重复注册同一 tab 以后者为准（账号切换会重建组件树）', 0, (): void => {
      const a = new FakeStack();
      const b = new FakeStack();
      registerStack('chat', a);
      registerStack('chat', b);
      expect(stackOf('chat') === b).assertTrue();
    });

    it('clearAllStacks 清掉每一条已注册的栈', 0, (): void => {
      const a = new FakeStack();
      const b = new FakeStack();
      a.pushPath({ name: 'ChatPage' });
      b.pushPath({ name: 'AboutPage' });
      registerStack('chat', a);
      registerStack('settings', b);
      clearAllStacks();
      expect(a.cleared).assertEqual(1);
      expect(b.cleared).assertEqual(1);
      expect(a.size()).assertEqual(0);
      expect(b.size()).assertEqual(0);
    });

    it('clearAllStacks 不会因某个 tab 没注册而抛', 0, (): void => {
      const a = new FakeStack();
      registerStack('chat', a);
      clearAllStacks();
      expect(a.cleared).assertEqual(1);
    });

    it('snapshotOf 空栈得到空数组', 0, (): void => {
      const s = new FakeStack();
      const snap: StackFrame[] = snapshotOf(s, idKey);
      expect(snap.length).assertEqual(0);
    });

    it('snapshotOf 按顺序还原 name 与 key', 0, (): void => {
      const s = new FakeStack();
      const p1: Record<string, Object> = { 'id': 10 };
      const p2: Record<string, Object> = { 'id': 20 };
      s.pushPath({ name: 'ChatPage', param: p1 });
      s.pushPath({ name: 'ProfilePage', param: p2 });
      const snap: StackFrame[] = snapshotOf(s, idKey);
      expect(snap.length).assertEqual(2);
      expect(snap[0].name).assertEqual('ChatPage');
      expect(snap[0].key).assertEqual('10');
      expect(snap[1].name).assertEqual('ProfilePage');
      expect(snap[1].key).assertEqual('20');
    });

  });
}
