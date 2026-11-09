import { describe, expect, it } from '@ohos/hypium';
import {
  MediaViewerResult, publishViewerData, publishViewerResult, requestMediaSave,
  requestViewerHistory, resetMediaViewerChannel, subscribeMediaSave,
  subscribeViewerData, subscribeViewerHistory, subscribeViewerResult
} from '../main/ets/util/mediaViewerChannel';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import { MessageEntry } from '../main/ets/store/MessageEntry';

// 全屏查看器跨页通道的测试（S4 批）。
//
// 四条通道形状同构，但**语义各不相同**，逐条钉住的是各自的那一条契约：
//   data    —— 多播、按 chatId 隔离
//   result  —— **同步**（播放位交接依赖它早于 ChatPage.onShown）
//   save    —— 参数原样透传
//   history —— dir 的符号语义
//
// 每条另有一份"退订之后不再收到"，防的是退订函数写错导致查看器关掉之后
// ChatPage 还在往一个死掉的页面推数据。
//
// 模块级 Map 跨用例活着，所以每条用例开头都要 resetMediaViewerChannel()
// （照 ChatJumpChannel.test.ets 的做法）。

const CHAT_A: number = 1001;
const CHAT_B: number = 2002;

export default function mediaViewerChannelTest() {
  describe('MediaViewerChannel', () => {

    // ——— data ———

    it('data：发布的 messages/groups 原样送到订阅者', 0, () => {
      resetMediaViewerChannel();
      let gotMsgs: MessageEntry[] = [];
      let gotGroups: AlbumGroup[] = [];
      let calls: number = 0;
      subscribeViewerData(CHAT_A, (m: MessageEntry[], g: AlbumGroup[]): void => {
        calls++;
        gotMsgs = m;
        gotGroups = g;
      });

      const msgs: MessageEntry[] = [];
      const groups: AlbumGroup[] = [];
      publishViewerData(CHAT_A, msgs, groups);

      expect(calls).assertEqual(1);
      // 断言的是**同一个引用**：查看器必须拿到 ChatPage 已 commit 的那一份，
      // 不是拷贝，也不是自己现算的（见通道文件头第 1 条）。
      expect(gotMsgs === msgs).assertTrue();
      expect(gotGroups === groups).assertTrue();
    });

    it('data：按 chatId 隔离，另一个会话的订阅者收不到', 0, () => {
      resetMediaViewerChannel();
      let aCalls: number = 0;
      let bCalls: number = 0;
      subscribeViewerData(CHAT_A, (): void => { aCalls++; });
      subscribeViewerData(CHAT_B, (): void => { bCalls++; });

      publishViewerData(CHAT_A, [], []);

      expect(aCalls).assertEqual(1);
      expect(bCalls).assertEqual(0);
    });

    it('data：退订之后不再收到', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      const off: () => void = subscribeViewerData(CHAT_A, (): void => { calls++; });

      publishViewerData(CHAT_A, [], []);
      off();
      publishViewerData(CHAT_A, [], []);

      expect(calls).assertEqual(1);
    });

    it('data：没有订阅者时静默丢弃，不排队', 0, () => {
      resetMediaViewerChannel();
      publishViewerData(CHAT_A, [], []);   // 没有订阅者，不该抛

      let calls: number = 0;
      subscribeViewerData(CHAT_A, (): void => { calls++; });
      // 订阅之后不该补送上一条——留待送队列会在下次打开时冒出陈旧数据。
      expect(calls).assertEqual(0);
    });

    // ——— result ———

    // 这条是四条里最要紧的：播放位交接依赖回传**同步**发生，
    // 因为它必须早于 ChatPage.onShown 里的 armPlaySlotSettle()。
    it('result：回传是同步的，publish 返回时订阅者已经跑完', 0, () => {
      resetMediaViewerChannel();
      // 直接捕字段而不是存一个 MediaViewerResult | null：ArkTS 不允许把 null
      // 强转回接口类型（arkts 严格窄化），而这条用例要断言的本来就是"同步收到"
      // 与三个字段的值，不需要持有那个对象。
      let calls: number = 0;
      let msgId: number = 0;
      let albumIdx: number = -99;
      let posMs: number = -1;
      subscribeViewerResult(CHAT_A, (r: MediaViewerResult): void => {
        calls++;
        msgId = r.messageId;
        albumIdx = r.albumIndex;
        posMs = r.positionMs;
      });

      publishViewerResult(CHAT_A, { messageId: 7, albumIndex: -1, positionMs: 12000 });

      // 不 await、不 sleep——publish 返回的这一刻就必须已经收到。
      expect(calls).assertEqual(1);
      expect(msgId).assertEqual(7);
      expect(albumIdx).assertEqual(-1);
      expect(posMs).assertEqual(12000);
    });

    it('result：相册成员的 albumIndex 原样透传', 0, () => {
      resetMediaViewerChannel();
      let idx: number = -99;
      subscribeViewerResult(CHAT_A, (r: MediaViewerResult): void => { idx = r.albumIndex; });

      publishViewerResult(CHAT_A, { messageId: 7, albumIndex: 2, positionMs: 0 });

      expect(idx).assertEqual(2);
    });

    it('result：退订之后不再收到', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      const off: () => void = subscribeViewerResult(CHAT_A, (): void => { calls++; });

      publishViewerResult(CHAT_A, { messageId: 1, albumIndex: -1, positionMs: 0 });
      off();
      publishViewerResult(CHAT_A, { messageId: 1, albumIndex: -1, positionMs: 0 });

      expect(calls).assertEqual(1);
    });

    // ——— save ———

    it('save：messageId 与 toFiles 原样透传', 0, () => {
      resetMediaViewerChannel();
      let gotId: number = 0;
      let gotToFiles: boolean = false;
      subscribeMediaSave(CHAT_A, (messageId: number, toFiles: boolean): void => {
        gotId = messageId;
        gotToFiles = toFiles;
      });

      requestMediaSave(CHAT_A, 42, true);

      expect(gotId).assertEqual(42);
      expect(gotToFiles).assertTrue();
    });

    it('save：非法 messageId 不发', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      subscribeMediaSave(CHAT_A, (): void => { calls++; });

      requestMediaSave(CHAT_A, 0, false);
      requestMediaSave(CHAT_A, -1, false);

      expect(calls).assertEqual(0);
    });

    // ——— history ———

    // dir 的符号语义与今天 MediaViewerOverlay 的 onNeedHistory(dir) 逐字相同：
    // < 0 拉更早，> 0 拉更新。搬迁时把符号搞反是静默故障（翻到头拉错方向，
    // 表现为"翻不动"而不是报错）。
    it('history：dir 的符号原样透传', 0, () => {
      resetMediaViewerChannel();
      const dirs: number[] = [];
      subscribeViewerHistory(CHAT_A, (dir: number): void => { dirs.push(dir); });

      requestViewerHistory(CHAT_A, -1);
      requestViewerHistory(CHAT_A, 1);

      expect(dirs.length).assertEqual(2);
      expect(dirs[0]).assertEqual(-1);
      expect(dirs[1]).assertEqual(1);
    });

    it('history：dir 为 0 不发', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      subscribeViewerHistory(CHAT_A, (): void => { calls++; });

      requestViewerHistory(CHAT_A, 0);

      expect(calls).assertEqual(0);
    });

    // ——— 跨通道 ———

    it('reset 清掉全部四条通道', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      subscribeViewerData(CHAT_A, (): void => { calls++; });
      subscribeViewerResult(CHAT_A, (): void => { calls++; });
      subscribeMediaSave(CHAT_A, (): void => { calls++; });
      subscribeViewerHistory(CHAT_A, (): void => { calls++; });

      resetMediaViewerChannel();

      publishViewerData(CHAT_A, [], []);
      publishViewerResult(CHAT_A, { messageId: 1, albumIndex: -1, positionMs: 0 });
      requestMediaSave(CHAT_A, 1, false);
      requestViewerHistory(CHAT_A, -1);

      expect(calls).assertEqual(0);
    });

    it('chatId 为 0 一律不发（四条通道各一次）', 0, () => {
      resetMediaViewerChannel();
      let calls: number = 0;
      subscribeViewerData(0, (): void => { calls++; });
      subscribeViewerResult(0, (): void => { calls++; });
      subscribeMediaSave(0, (): void => { calls++; });
      subscribeViewerHistory(0, (): void => { calls++; });

      publishViewerData(0, [], []);
      publishViewerResult(0, { messageId: 1, albumIndex: -1, positionMs: 0 });
      requestMediaSave(0, 1, false);
      requestViewerHistory(0, -1);

      expect(calls).assertEqual(0);
    });
  });
}
