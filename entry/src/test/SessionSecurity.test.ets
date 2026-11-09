import { describe, expect, it } from '@ohos/hypium';
import { SessionSecurityStore } from '../main/ets/store/SessionSecurityStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';

class SecurityBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  sent: TdObject[] = [];
  init(callback: (json: string) => void): void { this.receive = callback; }
  send(json: string): void { this.sent.push(JSON.parse(json) as TdObject); }
  reply(index: number, object: TdObject): void {
    object['@extra'] = this.sent[index]['@extra'];
    this.receive(JSON.stringify(object));
  }
  push(count: number, model: string = 'Phone'): void {
    const summary: TdObject = { '@type': 'unconfirmedSession' };
    summary['date'] = 100; summary['device_model'] = model; summary['location'] = 'Somewhere';
    const update: TdObject = { '@type': 'updateUnconfirmedSession' };
    update['unconfirmed_session_count'] = count;
    if (count > 0) { update['session'] = summary; }
    this.receive(JSON.stringify(update));
  }
}
function sessions(count: number): TdObject {
  const current: TdObject = { '@type': 'session' }; current['id'] = '1'; current['is_current'] = true;
  const rows: TdObject[] = [current];
  for (let i = 0; i < count; i++) {
    const row: TdObject = { '@type': 'session' };
    row['id'] = `${i + 2}`; row['is_unconfirmed'] = true; rows.push(row);
  }
  const result: TdObject = { '@type': 'sessions' }; result['sessions'] = rows; return result;
}
class SecurityHarness {
  bridge: SecurityBridge = new SecurityBridge();
  client: TdClient = new TdClient(this.bridge);
  store: SessionSecurityStore = new SessionSecurityStore(this.client);
  count: number = -1;
  events: number = 0;
  constructor() {
    this.store.subscribe((count: number): void => { this.count = count; });
    this.store.onChange((): void => { this.events++; });
    this.client.start();
  }
  close(): void { this.store.close(); this.client.dispose(); }
}
async function rejected(operation: Promise<Object | void>): Promise<boolean> {
  try { await operation; return false; } catch (_) { return true; }
}
export default function sessionSecurityTest() {
  describe('SessionSecurity', () => {
    it('冷启动读取完整列表填充待确认数量', 0, async (): Promise<void> => {
      const h = new SecurityHarness();
      expect(h.count).assertEqual(0);
      const pending = h.store.read();
      h.bridge.reply(0, sessions(2));
      expect(h.store.isCurrent(await pending)).assertTrue();
      expect(h.count).assertEqual(2); expect(h.events).assertEqual(0);
      h.close();
    });
    it('收到新设备推送实时更新提醒但不主动轮询', 0, (): void => {
      const h = new SecurityHarness(); h.bridge.push(1);
      expect(h.count).assertEqual(1); expect(h.events).assertEqual(1);
      expect(h.bridge.sent.length).assertEqual(0); h.close();
    });
    it('重复推送去重，相同数量不同设备仍触发列表更新', 0, (): void => {
      const h = new SecurityHarness(); h.bridge.push(1); h.bridge.push(1);
      expect(h.events).assertEqual(1);
      h.bridge.push(1, 'Laptop'); expect(h.events).assertEqual(2); h.close();
    });
    it('其他设备完成确认后数量清零', 0, (): void => {
      const h = new SecurityHarness(); h.bridge.push(2); h.bridge.push(0);
      expect(h.count).assertEqual(0); expect(h.events).assertEqual(2); h.close();
    });
    it('订阅晚于推送仍立即收到当前计数', 0, (): void => {
      const h = new SecurityHarness(); h.bridge.push(3); let replay = -1;
      h.store.subscribe((count: number): void => { replay = count; });
      expect(replay).assertEqual(3); h.close();
    });
    it('请求期间新推送使旧列表失效，不能覆盖提醒', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); const pending = h.store.read();
      h.bridge.push(2); h.bridge.reply(0, sessions(0));
      expect(h.store.isCurrent(await pending)).assertFalse(); expect(h.count).assertEqual(2); h.close();
    });
    it('并发读取合并为一次TD请求', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); const first = h.store.read(); const second = h.store.read();
      expect(h.bridge.sent.length).assertEqual(1); h.bridge.reply(0, sessions(1));
      expect((await first).response).assertEqual((await second).response); h.close();
    });
    it('失效请求完成后可以重新获取当前快照', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); const first = h.store.read(); h.bridge.push(1);
      h.bridge.reply(0, sessions(0)); await first;
      const second = h.store.read(); h.bridge.reply(1, sessions(1));
      expect(h.store.isCurrent(await second)).assertTrue(); expect(h.count).assertEqual(1); h.close();
    });
    it('缺当前会话的异常列表不会把提醒错误清零', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); h.bridge.push(1);
      const pending = rejected(h.store.read());
      const result: TdObject = { '@type': 'sessions' }; result['sessions'] = [];
      h.bridge.reply(0, result); expect(await pending).assertTrue(); expect(h.count).assertEqual(1); h.close();
    });
    it('读取失败保留提醒且允许用户重试', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); h.bridge.push(2); const pending = rejected(h.store.read());
      const error: TdObject = { '@type': 'error' }; error['code'] = 500; error['message'] = 'network';
      h.bridge.reply(0, error); expect(await pending).assertTrue(); expect(h.count).assertEqual(2);
      const retry = h.store.read(); h.bridge.reply(1, sessions(1)); await retry;
      expect(h.count).assertEqual(1); h.close();
    });
    it('关闭运行时清零并阻止旧回包复活提醒', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); h.bridge.push(1); const pending = h.store.read();
      h.store.close(); expect(h.count).assertEqual(0); h.bridge.reply(0, sessions(4));
      expect(h.store.isCurrent(await pending)).assertFalse(); expect(h.count).assertEqual(0);
      expect(await rejected(h.store.read())).assertTrue(); h.close();
    });
    it('多账号实例隔离，关闭旧账号不清新账号', 0, (): void => {
      const a = new SecurityHarness(); const b = new SecurityHarness();
      a.bridge.push(1); b.bridge.push(2); a.close();
      expect(b.count).assertEqual(2); b.close();
    });
    it('页面失效时不能提交确认请求', 0, async (): Promise<void> => {
      const h = new SecurityHarness();
      expect(await rejected(h.store.mutate({ '@type': 'confirmSession' }, (): boolean => false))).assertTrue();
      expect(h.bridge.sent.length).assertEqual(0); h.close();
    });
    it('确认在途页面退出，成功回包也按失效处理', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); let active = true;
      const pending = rejected(h.store.mutate({ '@type': 'confirmSession' }, (): boolean => active));
      active = false; h.bridge.reply(0, { '@type': 'ok' });
      expect(await pending).assertTrue(); h.close();
    });
    it('写操作使之前列表失效，不按本地成功盲减计数', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); h.bridge.push(1); const read = h.store.read();
      const request: TdRequest = { '@type': 'confirmSession' }; request['session_id'] = '9007199254740999';
      const write = h.store.mutate(request, (): boolean => true);
      expect(h.bridge.sent[1]['session_id']).assertEqual('9007199254740999');
      h.bridge.reply(1, { '@type': 'ok' }); await write;
      h.bridge.reply(0, sessions(1)); expect(h.store.isCurrent(await read)).assertFalse();
      expect(h.count).assertEqual(1);
      const refreshed = h.store.read(); h.bridge.reply(2, sessions(0)); await refreshed;
      expect(h.count).assertEqual(0); h.close();
    });
    it('写失败不自动重试或误报成功', 0, async (): Promise<void> => {
      const h = new SecurityHarness(); const pending = rejected(h.store.mutate({ '@type': 'terminateSession' }, (): boolean => true));
      const error: TdObject = { '@type': 'error' }; error['code'] = 500; error['message'] = 'failed';
      h.bridge.reply(0, error); expect(await pending).assertTrue(); expect(h.bridge.sent.length).assertEqual(1); h.close();
    });
    it('取消订阅后不再回调，关闭后的订阅只返回空状态', 0, (): void => {
      const h = new SecurityHarness(); let calls = 0;
      const off = h.store.subscribe((_count: number): void => { calls++; }); off(); h.bridge.push(1);
      expect(calls).assertEqual(1); h.store.close(); let count = -1;
      h.store.subscribe((value: number): void => { count = value; }); expect(count).assertEqual(0); h.close();
    });
  });
}
