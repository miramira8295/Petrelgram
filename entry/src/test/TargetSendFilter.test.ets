import { describe, expect, it } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TargetSendFilter } from '../main/ets/services/TargetSendFilter';
import { TdObject, TdRequest, TdBridge } from '../main/ets/tdkit/TdTypes';
import { GroupPermissions, allPermissions, permissionsToTd } from '../main/ets/util/chatPermissions';

class UpdateBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  init(callback: (json: string) => void): void { this.receive = callback; }
  send(_json: string): void {}
}
class FilterPort {
  values: Map<number, GroupPermissions> = new Map();
  statuses: Map<number, TdObject> = new Map();
  failures: Set<number> = new Set();
  channels: Set<number> = new Set();
  reads: number[] = [];
  hold: boolean = false;
  replies: (() => void)[] = [];
  send = async (request: TdRequest): Promise<TdObject> => {
    const id = (request['chat_id'] ?? request['supergroup_id']) as number;
    if (this.failures.has(id)) { throw new Error('unavailable'); }
    if (request['@type'] === 'getChat') {
      this.reads.push(id);
      const result: TdObject = { '@type': 'chat',
        'permissions': permissionsToTd(this.values.get(id) ?? allPermissions(true)),
        'type': { '@type': 'chatTypeSupergroup', 'supergroup_id': id,
          'is_channel': this.channels.has(id) } as TdObject };
      if (this.hold) { await new Promise<void>((resolve: () => void): void => { this.replies.push(resolve); }); }
      return result;
    }
    return { '@type': 'supergroup', 'status': this.statuses.get(id) ?? ({ '@type': 'chatMemberStatusMember' } as TdObject) };
  };
  release(): void { const replies = this.replies; this.replies = []; replies.forEach((reply: () => void): void => reply()); }
}
async function settle(): Promise<void> { await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); }); }
function create(port: FilterPort, keys: string[]): TargetSendFilter {
  const filter = new TargetSendFilter(port.send, async (): Promise<string[]> => keys, (): void => {}, (): boolean => true);
  filter.reload(); return filter;
}
export default function targetSendFilterTest() {
  describe('TargetSendFilter', () => {
    it('仅相关聊天权限更新使缓存失效', 0, async () => {
      const port = new FilterPort(); const bridge = new UpdateBridge(); const client = new TdClient(bridge); client.start();
      const filter = new TargetSendFilter(port.send, async (): Promise<string[]> => ['sendPhotos'], (): void => {}, (): boolean => true);
      filter.bind(client); filter.include([1]); await settle();
      bridge.receive(JSON.stringify({ '@type': 'updateChatPermissions', 'chat_id': 99 }));
      bridge.receive(JSON.stringify({ '@type': 'updateSupergroup', 'supergroup': { 'id': 99 } as TdObject }));
      await settle(); expect(port.reads.length).assertEqual(1);
      const value = allPermissions(true); value.sendPhotos = false; port.values.set(1, value);
      bridge.receive(JSON.stringify({ '@type': 'updateSupergroup', 'supergroup': { 'id': 1 } as TdObject }));
      await settle(); expect(port.reads.length).assertEqual(2); expect(filter.allowedIds().length).assertEqual(0); filter.dispose();
    });
    it('快照名单更换后丢弃移出目标的延迟响应', 0, async () => {
      const port = new FilterPort(); port.hold = true; const filter = create(port, ['sendPhotos']);
      filter.retain([1]); await settle(); filter.retain([2]); port.hold = false; port.release(); await settle();
      expect(filter.allowedIds().join(',')).assertEqual('2'); expect(filter.permissionKeys(1)).assertNull(); filter.dispose();
    });
    it('禁文件群从文件列表隐藏但文本仍可选', 0, async () => {
      const port = new FilterPort(); const value = allPermissions(true); value.sendDocuments = false;
      port.values.set(1, value);
      const file = create(port, ['sendDocuments']); file.include([1, 2]); await settle();
      expect(file.allowedIds().join(',')).assertEqual('2'); file.dispose();
      const text = create(port, ['sendMessages']); text.include([1]); await settle();
      expect(text.allowedIds().join(',')).assertEqual('1'); text.dispose();
    });
    it('照片和视频分别使用对应权限', 0, async () => {
      const port = new FilterPort(); const value = allPermissions(true); value.sendPhotos = false; port.values.set(1, value);
      const photo = create(port, ['sendPhotos']); photo.include([1]); await settle(); expect(photo.allowedIds().length).assertEqual(0); photo.dispose();
      const video = create(port, ['sendVideos']); video.include([1]); await settle(); expect(video.allowedIds().length).assertEqual(1); video.dispose();
    });
    it('贴纸GIF禁发群不进入候选', 0, async () => {
      const port = new FilterPort(); const value = allPermissions(true); value.sendOtherMessages = false; port.values.set(1, value);
      const filter = create(port, ['sendOtherMessages']); filter.include([1, 2]); await settle();
      expect(filter.allowedIds().join(',')).assertEqual('2'); filter.dispose();
    });
    it('混合转发必须允许全部类型', 0, async () => {
      const port = new FilterPort(); const value = allPermissions(true); value.sendDocuments = false; port.values.set(1, value);
      const filter = create(port, ['sendPhotos', 'sendDocuments']); filter.include([1, 2]); await settle();
      expect(filter.allowedIds().join(',')).assertEqual('2'); filter.dispose();
    });
    it('管理员权限覆盖群默认限制', 0, async () => {
      const port = new FilterPort(); port.values.set(1, allPermissions(false));
      port.statuses.set(1, { '@type': 'chatMemberStatusAdministrator' });
      const filter = create(port, ['sendPhotos', 'sendDocuments']); filter.include([1]); await settle();
      expect(filter.allowedIds().join(',')).assertEqual('1'); filter.dispose();
    });
    it('个人禁发权限与群权限共同生效', 0, async () => {
      const port = new FilterPort(); const own = allPermissions(true); own.sendDocuments = false;
      port.statuses.set(1, { '@type': 'chatMemberStatusRestricted', 'is_member': true, 'permissions': permissionsToTd(own) });
      const filter = create(port, ['sendDocuments']); filter.include([1]); await settle();
      expect(filter.allowedIds().length).assertEqual(0); filter.dispose();
    });
    it('频道未获得发帖权限时隐藏', 0, async () => {
      const port = new FilterPort(); port.channels.add(1);
      const filter = create(port, ['sendMessages']); filter.include([1]); await settle();
      expect(filter.allowedIds().length).assertEqual(0); filter.dispose();
    });
    it('未知权限不先展示且限制六项并发', 0, async () => {
      const port = new FilterPort(); port.hold = true;
      const filter = create(port, ['sendDocuments']); filter.include([1, 2, 3, 4, 5, 6, 7, 8]); await settle();
      expect(port.reads.length).assertEqual(6); expect(filter.allowedIds().length).assertEqual(0); expect(filter.checking()).assertTrue();
      port.hold = false; port.release(); await settle();
      expect(filter.allowedIds().length).assertEqual(8); expect(filter.checking()).assertFalse(); filter.dispose();
    });
    it('单目标查询失败只隐藏该目标', 0, async () => {
      const port = new FilterPort(); port.failures.add(1);
      const filter = create(port, ['sendPhotos']); filter.include([1, 2]); await settle();
      expect(filter.allowedIds().join(',')).assertEqual('2'); expect(filter.checking()).assertFalse(); expect(filter.failed()).assertFalse(); filter.dispose();
    });
    it('源内容读取失败不展示目标并可重试', 0, async () => {
      const port = new FilterPort(); let fail: boolean = true;
      const filter = new TargetSendFilter(port.send, async (): Promise<string[]> => {
        if (fail) { throw new Error('missing source'); } return ['sendPhotos'];
      }, (): void => {}, (): boolean => true);
      filter.include([1]); filter.reload(); await settle();
      expect(filter.failed()).assertTrue(); expect(filter.allowedIds().length).assertEqual(0);
      fail = false; filter.reload(); await settle(); expect(filter.allowedIds().join(',')).assertEqual('1'); filter.dispose();
    });
    it('权限失效后丢弃旧响应并重新计算', 0, async () => {
      const port = new FilterPort(); port.hold = true;
      const filter = create(port, ['sendDocuments']); filter.include([1]); await settle();
      const value = allPermissions(true); value.sendDocuments = false; port.values.set(1, value);
      filter.invalidate(); port.hold = false; port.release(); await settle();
      expect(filter.allowedIds().length).assertEqual(0); expect(filter.checking()).assertFalse(); filter.dispose();
    });
    it('离页或切账号后旧响应不发布', 0, async () => {
      const port = new FilterPort(); port.hold = true; let active: boolean = true; let changed: number = 0;
      const filter = new TargetSendFilter(port.send, async (): Promise<string[]> => ['sendPhotos'],
        (): void => { changed++; }, (): boolean => active);
      filter.reload(); filter.include([1]); await settle(); const before = changed;
      active = false; port.release(); await settle(); expect(changed).assertEqual(before); expect(filter.allowedIds().length).assertEqual(0); filter.dispose();
      const disposed = create(port, ['sendPhotos']); disposed.include([2]); await settle(); disposed.dispose();
      port.release(); await settle(); expect(disposed.allowedIds().length).assertEqual(0);
    });
    it('常用文件夹搜索复用同一目标权限缓存', 0, async () => {
      const port = new FilterPort(); const filter = create(port, ['sendPhotos']);
      filter.include([1, 2]); await settle(); filter.include([2, 3, 1, 0]); await settle();
      expect(port.reads.join(',')).assertEqual('1,2,3'); expect(filter.permissionKeys(1)!.includes('sendPhotos')).assertTrue();
      expect(filter.permissionKeys(999)).assertNull(); filter.dispose();
    });
  });
}
