import { describe, expect, it } from '@ohos/hypium';
import { WallpaperEditorSession, WallpaperEditorSource } from '../main/ets/services/WallpaperEditorSession';
import { ChatBackgroundState, emptyChatBackground } from '../main/ets/store/ChatBackgroundStore';

class Source implements WallpaperEditorSource {
  seeded: number = 0;
  opened: number[] = [];
  closed: number = 0;
  unsubscribed: number = 0;
  callback: (state: ChatBackgroundState) => void = (): void => {};
  seedFromDefault(): void { this.seeded++; }
  subscribe(callback: (state: ChatBackgroundState) => void): () => void {
    this.callback = callback; callback(emptyChatBackground());
    return (): void => { this.unsubscribed++; };
  }
  open(chatId: number): void { this.opened.push(chatId); }
  close(): void { this.closed++; }
}
export default function wallpaperEditorSessionTest() {
  describe('WallpaperEditorSession', () => {
    it('默认槽位先播快照并持续接收解析和下载结果', 0, () => {
      const session = new WallpaperEditorSession(); const source = new Source(); const states: ChatBackgroundState[] = [];
      session.open(source, 0, (): boolean => true, (state: ChatBackgroundState): void => { states.push(state); });
      const pattern = emptyChatBackground(); pattern.custom = true; pattern.isPattern = true; pattern.colors = ['#112233'];
      source.callback(pattern); const ready = emptyChatBackground(); ready.isPattern = true; ready.path = '/pattern.svg'; source.callback(ready);
      expect(source.seeded).assertEqual(1); expect(source.opened[0]).assertEqual(0);
      expect(states.length).assertEqual(3); expect(states[1].isPattern).assertTrue(); expect(states[2].path).assertEqual('/pattern.svg'); session.close();
    });
    it('专属会话解析不使用账号默认快照冒充初始背景', 0, () => {
      const session = new WallpaperEditorSession(); const source = new Source();
      session.open(source, -123, (): boolean => true, (): void => {});
      expect(source.seeded).assertEqual(0); expect(source.opened[0]).assertEqual(-123); session.close();
    });
    it('切换深浅槽位后旧回调不能覆盖新槽位', 0, () => {
      const session = new WallpaperEditorSession(); const light = new Source(); const dark = new Source(); let path: string = '';
      const publish = (state: ChatBackgroundState): void => { path = state.path; };
      session.open(light, 0, (): boolean => true, publish); session.open(dark, 0, (): boolean => true, publish);
      const current = emptyChatBackground(); current.path = '/dark'; dark.callback(current);
      const stale = emptyChatBackground(); stale.path = '/light'; light.callback(stale);
      expect(path).assertEqual('/dark'); expect(light.closed).assertEqual(1); expect(light.unsubscribed).assertEqual(1); session.close();
    });
    it('用户选择本机图前关闭会话后迟到的远端结果不覆盖', 0, () => {
      const session = new WallpaperEditorSession(); const source = new Source(); let count: number = 0;
      session.open(source, 0, (): boolean => true, (): void => { count++; }); session.close();
      source.callback(emptyChatBackground()); expect(count).assertEqual(1); expect(source.closed).assertEqual(1);
    });
    it('账号失活后结果不发布', 0, () => {
      const session = new WallpaperEditorSession(); const source = new Source(); let active: boolean = true; let count: number = 0;
      session.open(source, 0, (): boolean => active, (): void => { count++; }); active = false;
      source.callback(emptyChatBackground()); expect(count).assertEqual(1); session.close();
    });
    it('重复关闭只注销一次且可以重新打开', 0, () => {
      const session = new WallpaperEditorSession(); const source = new Source();
      session.open(source, 0, (): boolean => true, (): void => {}); session.close(); session.close();
      expect(source.closed).assertEqual(1); expect(source.unsubscribed).assertEqual(1);
      session.open(source, 0, (): boolean => true, (): void => {}); expect(source.opened.length).assertEqual(2); session.close();
    });
  });
}
