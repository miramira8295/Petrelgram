import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import { StickerPreviewClient, StickerPreviewData, StickerPreviewSession, StickerPreviewSnapshot,
  emptyStickerPreview } from '../main/ets/pages/chat/StickerPreviewSession';
interface PreviewPending {
  request: TdRequest;
  resolve: (result: TdObject) => void;
  reject: (error: Error) => void;
}
class PreviewClient implements StickerPreviewClient {
  pending: PreviewPending[] = [];
  send: (request: TdRequest, timeout: number) => Promise<TdObject> = (request: TdRequest, _timeout: number): Promise<TdObject> => {
    return new Promise<TdObject>((resolve, reject): void => { this.pending.push({ request, resolve, reject }); });
  };
}
class PreviewHarness {
  client: PreviewClient = new PreviewClient();
  current: boolean = true;
  state: StickerPreviewSnapshot = emptyStickerPreview();
  changes: boolean[] = [];
  session: StickerPreviewSession;
  constructor(canFavorite: boolean = true) {
    const data: StickerPreviewData = { fileId: 12, format: 'tgs', emoji: '', thumbPath: '', width: 512, height: 512, canFavorite };
    this.session = new StickerPreviewSession(this.client, data, (): boolean => this.current,
      (state: StickerPreviewSnapshot): void => { this.state = state; },
      (favorite: boolean): void => { this.changes.push(favorite); });
  }
}
function file(path: string, complete: boolean = true): TdObject {
  const local: TdObject = { '@type': 'localFile' }; local['path'] = path; local['is_downloading_completed'] = complete;
  const remote: TdObject = { '@type': 'remoteFile' }; remote['unique_id'] = 'stable-id';
  const result: TdObject = { '@type': 'file' }; result['local'] = local; result['remote'] = remote; return result;
}
function favorites(has: boolean): TdObject {
  const source: TdObject = { '@type': 'file' }; source['id'] = 12;
  const sticker: TdObject = { '@type': 'sticker' }; sticker['sticker'] = source;
  const result: TdObject = { '@type': 'stickers' }; result['stickers'] = has ? [sticker] : []; return result;
}
async function settle(): Promise<void> { for (let i = 0; i < 8; i++) { await Promise.resolve(); } }
async function ready(h: PreviewHarness, has: boolean = false): Promise<void> {
  const read = h.session.loadFavorite(); h.client.pending[0].resolve(favorites(has)); await read;
}
export default function stickerPreviewTest() {
  describe('StickerPreview', () => {
    it('完整本地源文件直接预览而不重复下载', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const task = h.session.loadFile(); h.client.pending[0].resolve(file('/sticker.tgs')); await task;
      expect(h.client.pending.length).assertEqual(1); expect(h.state.path).assertEqual('/sticker.tgs');
      expect(h.state.uid).assertEqual('stable-id'); expect(h.state.loading).assertFalse();
    });
    it('未完成文件必须下载完成后才交给播放器', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const task = h.session.loadFile(); h.client.pending[0].resolve(file('/partial', false)); await settle();
      expect(h.client.pending[1].request['@type']).assertEqual('downloadFile'); expect(h.state.path).assertEqual('');
      h.client.pending[1].resolve(file('/complete')); await task; expect(h.state.path).assertEqual('/complete');
    });
    it('下载返回半文件显示错误而不播放', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const task = h.session.loadFile(); h.client.pending[0].resolve(file('', false)); await settle();
      h.client.pending[1].resolve(file('/partial', false)); await task; expect(h.state.failed).assertTrue(); expect(h.state.path).assertEqual('');
    });
    it('关闭后getFile返回不再启动下载', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const task = h.session.loadFile(); h.session.close();
      h.client.pending[0].resolve(file('', false)); await task; expect(h.client.pending.length).assertEqual(1);
    });
    it('关闭预览后下载迟到不能恢复播放', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const task = h.session.loadFile(); h.client.pending[0].resolve(file('', false)); await settle();
      h.session.close(); h.client.pending[1].resolve(file('/late')); await task; expect(h.state.path).assertEqual('');
    });
    it('切账号后源文件与收藏响应不写入界面', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const source = h.session.loadFile(); const read = h.session.loadFavorite(); h.current = false;
      h.client.pending[0].resolve(file('/old-account')); h.client.pending[1].resolve(favorites(true)); await source; await read;
      expect(h.state.path).assertEqual(''); expect(h.state.favoriteReady).assertFalse();
    });
    it('较旧的源文件请求不能覆盖新重试', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const old = h.session.loadFile(); const fresh = h.session.loadFile();
      h.client.pending[1].resolve(file('/new')); await fresh; h.client.pending[0].resolve(file('/old')); await old;
      expect(h.state.path).assertEqual('/new');
    });
    it('收藏状态未读到时禁止猜测写入', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); await h.session.toggleFavorite(); expect(h.client.pending.length).assertEqual(0);
      await ready(h, true); expect(h.state.favorite).assertTrue();
    });
    it('收藏写操作期间重复点击只发一次', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); await ready(h); const write = h.session.toggleFavorite(); await h.session.toggleFavorite();
      expect(h.client.pending.length).assertEqual(2); expect(h.client.pending[1].request['@type']).assertEqual('addFavoriteSticker');
      h.client.pending[1].resolve({ '@type': 'ok' }); await write;
      expect(h.state.favorite).assertTrue(); expect(h.changes).assertDeepEquals([true]);
    });
    it('添加成功后下一次操作正确变成取消收藏', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); await ready(h); const add = h.session.toggleFavorite(); h.client.pending[1].resolve({ '@type': 'ok' }); await add;
      const remove = h.session.toggleFavorite(); expect(h.client.pending[2].request['@type']).assertEqual('removeFavoriteSticker');
      h.client.pending[2].resolve({ '@type': 'ok' }); await remove; expect(h.changes).assertDeepEquals([true, false]);
    });
    it('写入超时不自动重试，必须重读服务端状态', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); await ready(h); const write = h.session.toggleFavorite(); h.client.pending[1].reject(new Error('timeout')); await write;
      expect(h.state.favoriteFailed).assertTrue(); expect(h.state.favoriteReady).assertFalse();
      await h.session.toggleFavorite(); expect(h.client.pending.length).assertEqual(2);
      const read = h.session.loadFavorite(); h.client.pending[2].resolve(favorites(true)); await read;
      expect(h.state.favorite).assertTrue(); expect(h.state.favoriteReady).assertTrue();
    });
    it('关闭后写操作应答不修改其他页面收藏缓存', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); await ready(h); const write = h.session.toggleFavorite(); h.session.close();
      h.client.pending[1].resolve({ '@type': 'ok' }); await write; expect(h.changes.length).assertEqual(0);
    });
    it('收藏读取失败不伪装成未收藏', 0, async (): Promise<void> => {
      const h = new PreviewHarness(); const read = h.session.loadFavorite(); h.client.pending[0].reject(new Error('offline')); await read;
      expect(h.state.favoriteFailed).assertTrue(); expect(h.state.favoriteReady).assertFalse();
    });
    it('自定义表情不提供普通贴纸收藏能力', 0, async (): Promise<void> => {
      const h = new PreviewHarness(false); await h.session.loadFavorite(); await h.session.toggleFavorite();
      expect(h.client.pending.length).assertEqual(0);
    });
  });
}
