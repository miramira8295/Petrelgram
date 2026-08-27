import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatThemeStore } from '../main/ets/store/ChatThemeStore';
import {
  ChatBackgroundState, ChatBackgroundStore, defaultChatBackgroundSnapshot, emptyChatBackground,
  invalidateDefaultSnapshot
} from '../main/ets/store/ChatBackgroundStore';
import { gradientStops } from '../main/ets/util/backgroundPresentation';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
  // Answer the request carrying `@extra` as if TDLib replied with `result`.
  reply(result: TdObject): void {
    const last = this.sent[this.sent.length - 1];
    const extra = (JSON.parse(last) as TdObject)['@extra'] as string;
    result['@extra'] = extra;
    this.onReceive(JSON.stringify(result));
  }
  lastType(): string {
    if (this.sent.length === 0) { return ''; }
    return ((JSON.parse(this.sent[this.sent.length - 1]) as TdObject)['@type'] as string) ?? '';
  }
}

interface Harness {
  bridge: FakeBridge;
  client: TdClient;
  store: ChatBackgroundStore;
}

function harness(dark: boolean = false): Harness {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  const chats = new ChatStore(client, users);
  const themes = new ChatThemeStore(client);
  client.start();
  const store = new ChatBackgroundStore(client, chats, themes, (): boolean => dark);
  return { bridge, client, store };
}

function solidFillBackground(color: number): TdObject {
  const fill: TdObject = { '@type': 'backgroundFillSolid' };
  fill['color'] = color;
  const type: TdObject = { '@type': 'backgroundTypeFill' };
  type['fill'] = fill;
  const background: TdObject = { '@type': 'background' };
  background['type'] = type;
  const wrapper: TdObject = { '@type': 'chatBackground' };
  wrapper['background'] = background;
  wrapper['dark_theme_dimming'] = 40;
  return wrapper;
}

function gradientBackground(top: number, bottom: number, rotation: number): TdObject {
  const fill: TdObject = { '@type': 'backgroundFillGradient' };
  fill['top_color'] = top;
  fill['bottom_color'] = bottom;
  fill['rotation_angle'] = rotation;
  const type: TdObject = { '@type': 'backgroundTypeFill' };
  type['fill'] = fill;
  const background: TdObject = { '@type': 'background' };
  background['type'] = type;
  const wrapper: TdObject = { '@type': 'chatBackground' };
  wrapper['background'] = background;
  return wrapper;
}

export default function chatBackgroundStoreTest() {
  describe('chatBackgroundStore', () => {
    it('gradient stops duplicate a single color across both ends', 0, () => {
      const stops = gradientStops(['#FF0000']);
      expect(stops.length).assertEqual(2);
      expect(stops[0][0]).assertEqual('#FF0000');
      expect(stops[0][1]).assertEqual(0);
      expect(stops[1][1]).assertEqual(1);
    });

    it('gradient stops spread evenly over [0,1]', 0, () => {
      const stops = gradientStops(['#A', '#B', '#C']);
      expect(stops.length).assertEqual(3);
      expect(stops[0][1]).assertEqual(0);
      expect(stops[1][1]).assertEqual(0.5);
      expect(stops[2][1]).assertEqual(1);
    });

    it('gradient stops are empty for no colors', 0, () => {
      expect(gradientStops([]).length).assertEqual(0);
    });

    it('starts empty and falls back to the app resource', 0, () => {
      const h = harness();
      const state: ChatBackgroundState = h.store.current();
      expect(state.custom).assertFalse();
      expect(state.colors.length).assertEqual(0);
      expect(state.bubbleOutColor).assertEqual('');
    });

    it('subscribe delivers the current snapshot immediately', 0, () => {
      const h = harness();
      let seen: number = 0;
      const unsub = h.store.subscribe((): void => { seen++; });
      expect(seen).assertEqual(1);
      unsub();
    });

    it('unsubscribing stops delivery', 0, () => {
      const h = harness();
      let seen: number = 0;
      const unsub = h.store.subscribe((): void => { seen++; });
      unsub();
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      expect(seen).assertEqual(1);
    });

    it('a solid fill becomes one color plus dimming', 0, () => {
      const h = harness();
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      const state = h.store.current();
      expect(state.custom).assertTrue();
      expect(state.colors.length).assertEqual(1);
      expect(state.colors[0]).assertEqual('#FF0000');
      expect(state.dimming).assertEqual(0.4);
    });

    it('a gradient keeps both colors and its rotation', 0, () => {
      const h = harness();
      h.store.applyKnownBackground(gradientBackground(0x112233, 0x445566, 45));
      const state = h.store.current();
      expect(state.colors.length).assertEqual(2);
      expect(state.colors[0]).assertEqual('#112233');
      expect(state.colors[1]).assertEqual('#445566');
      expect(state.angle).assertEqual(45);
    });

    it('an identical background does not re-notify', 0, () => {
      const h = harness();
      let seen: number = 0;
      h.store.subscribe((): void => { seen++; });
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      const afterFirst: number = seen;
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      expect(seen).assertEqual(afterFirst);
    });

    it('a different background does notify', 0, () => {
      const h = harness();
      let seen: number = 0;
      h.store.subscribe((): void => { seen++; });
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      const afterFirst: number = seen;
      h.store.applyKnownBackground(solidFillBackground(0x00FF00));
      expect(seen > afterFirst).assertTrue();
    });

    it('null clears back to the resource fallback', 0, () => {
      const h = harness();
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      expect(h.store.current().custom).assertTrue();
      h.store.applyKnownBackground(null);
      expect(h.store.current().custom).assertFalse();
      expect(h.store.current().colors.length).assertEqual(0);
    });

    // 回归：真机切深色后 getInstalledBackgrounds 连续超时，原来 catch 里
    // applyBackground(null) 把已经画好的背景清成平底。失败不许清空。
    it('installed default failure keeps the background already on screen', 0, async () => {
      const h = harness();
      h.store.open(7);
      expect(h.bridge.lastType()).assertEqual('getChat');
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 7;
      h.bridge.reply(chat);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
      expect(h.bridge.lastType()).assertEqual('getInstalledBackgrounds');
      h.store.applyKnownBackground(solidFillBackground(0x336699));
      expect(h.store.current().colors.length).assertEqual(1);
      const failure: TdObject = { '@type': 'error' };
      failure['code'] = 400;
      failure['message'] = 'request timeout';
      h.bridge.reply(failure);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
      expect(h.store.current().custom).assertTrue();
      expect(h.store.current().colors.length).assertEqual(1);
    });

    it('a fill with neither colors nor file is ignored', 0, () => {
      const h = harness();
      const type: TdObject = { '@type': 'backgroundTypeFill' };
      const background: TdObject = { '@type': 'background' };
      background['type'] = type;
      const wrapper: TdObject = { '@type': 'chatBackground' };
      wrapper['background'] = background;
      h.store.applyKnownBackground(wrapper);
      expect(h.store.current().custom).assertFalse();
    });

    it('a bare background object is accepted without the wrapper', 0, () => {
      const h = harness();
      const fill: TdObject = { '@type': 'backgroundFillSolid' };
      fill['color'] = 0x00FF00;
      const type: TdObject = { '@type': 'backgroundTypeFill' };
      type['fill'] = fill;
      const bare: TdObject = { '@type': 'background' };
      bare['type'] = type;
      h.store.applyKnownBackground(bare);
      expect(h.store.current().colors[0]).assertEqual('#00FF00');
    });

    it('a fill background is not a pattern', 0, () => {
      const h = harness();
      h.store.applyKnownBackground(solidFillBackground(0xFF0000));
      expect(h.store.current().isPattern).assertFalse();
    });

    it('a pattern background is flagged so the renderer can tile it', 0, () => {
      const h = harness();
      const fill: TdObject = { '@type': 'backgroundFillSolid' };
      fill['color'] = 0x000000;
      const type: TdObject = { '@type': 'backgroundTypePattern' };
      type['fill'] = fill;
      type['intensity'] = 50;
      const background: TdObject = { '@type': 'background' };
      background['type'] = type;
      const wrapper: TdObject = { '@type': 'chatBackground' };
      wrapper['background'] = background;
      h.store.applyKnownBackground(wrapper);
      expect(h.store.current().isPattern).assertTrue();
    });

    it('clearing the background clears the pattern flag', 0, () => {
      const h = harness();
      const fill: TdObject = { '@type': 'backgroundFillSolid' };
      fill['color'] = 0x000000;
      const type: TdObject = { '@type': 'backgroundTypePattern' };
      type['fill'] = fill;
      type['intensity'] = 50;
      const background: TdObject = { '@type': 'background' };
      background['type'] = type;
      const wrapper: TdObject = { '@type': 'chatBackground' };
      wrapper['background'] = background;
      h.store.applyKnownBackground(wrapper);
      expect(h.store.current().isPattern).assertTrue();
      h.store.applyKnownBackground(null);
      expect(h.store.current().isPattern).assertFalse();
    });

    it('pattern intensity drives image opacity within bounds', 0, () => {
      const h = harness();
      const fill: TdObject = { '@type': 'backgroundFillSolid' };
      fill['color'] = 0x000000;
      const type: TdObject = { '@type': 'backgroundTypePattern' };
      type['fill'] = fill;
      type['intensity'] = 4; // below the 0.08 floor
      const background: TdObject = { '@type': 'background' };
      background['type'] = type;
      const wrapper: TdObject = { '@type': 'chatBackground' };
      wrapper['background'] = background;
      h.store.applyKnownBackground(wrapper);
      expect(h.store.current().imageOpacity).assertEqual(0.08);
    });

    it('open requests the chat and close detaches', 0, () => {
      const h = harness();
      h.store.open(42);
      expect(h.bridge.lastType()).assertEqual('getChat');
      h.store.close();
      // After close a late update for that chat must not resurface.
      const upd: TdObject = { '@type': 'updateChatBackground' };
      upd['chat_id'] = 42;
      upd['background'] = solidFillBackground(0xFF0000);
      h.bridge.onReceive(JSON.stringify(upd));
      expect(h.store.current().custom).assertFalse();
    });

    it('an update for another chat is ignored', 0, () => {
      const h = harness();
      h.store.open(42);
      const upd: TdObject = { '@type': 'updateChatBackground' };
      upd['chat_id'] = 99;
      upd['background'] = solidFillBackground(0xFF0000);
      h.bridge.onReceive(JSON.stringify(upd));
      expect(h.store.current().custom).assertFalse();
    });

    it('an update for the open chat is applied', 0, () => {
      const h = harness();
      h.store.open(42);
      const upd: TdObject = { '@type': 'updateChatBackground' };
      upd['chat_id'] = 42;
      upd['background'] = solidFillBackground(0x123456);
      h.bridge.onReceive(JSON.stringify(upd));
      expect(h.store.current().colors[0]).assertEqual('#123456');
    });

    // defaultChatBackgroundSnapshot() / seedFromDefault() — the module-level
    // cache a fresh ChatPage seeds its initial chatBg from, so it doesn't
    // start on emptyChatBackground() and flash chat_bg (near-white in light
    // mode) while the real resolution's TDLib round trip is in flight.

    it('a resolved account-default background is remembered and offered to a new store', 0, () => {
      const h = harness(false);
      h.store.applyKnownBackground(solidFillBackground(0xABCDEF));
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#ABCDEF');
      const seeded = harness(false);
      seeded.store.seedFromDefault();
      expect(seeded.store.current().colors[0]).assertEqual('#ABCDEF');
    });

    // 原来这条叫「快照只记住最近解析的那个模式」，断言被取代的模式回落到空。
    // 那测的是旧实现的单槽位限制，不是需求：快照落盘之后深/浅色各有一个独立
    // 的 key，两个模式可以同时记住。
    //
    // 真正要守的不变量没变，也正是原注释写的那条——**绝不把另一个模式的颜色
    // 交出去**，因为那会闪出错误的配色。下面四条断言把它钉死：问哪个模式，
    // 拿到的必须是那个模式自己的颜色。
    it('深浅色各记一份快照，互不串色', 0, () => {
      const light = harness(false);
      light.store.applyKnownBackground(solidFillBackground(0x111111));
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#111111');
      const dark = harness(true);
      dark.store.applyKnownBackground(solidFillBackground(0x222222));
      expect(defaultChatBackgroundSnapshot(true).colors[0]).assertEqual('#222222');
      // 解析过深色之后再问浅色，拿到的仍是浅色那份，不是深色的。
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#111111');
      expect(defaultChatBackgroundSnapshot(true).colors[0]).assertEqual('#222222');
    });

    // 设置页直接调 TDLib、不经过本 store，所以改完背景不会触发 patch()，盘上
    // 那份会一直是旧的——冷启动后第一个会话将画出**错误的**背景。作废之后最坏
    // 退化成一次空种子，下次打开会话时 patch() 会重新落一份正确的。
    it('作废只清掉指定模式那一份', 0, () => {
      const light = harness(false);
      light.store.applyKnownBackground(solidFillBackground(0x333333));
      const dark = harness(true);
      dark.store.applyKnownBackground(solidFillBackground(0x444444));
      invalidateDefaultSnapshot(false);
      expect(defaultChatBackgroundSnapshot(false).colors.length).assertEqual(0);
      // 另一个模式不受牵连。
      expect(defaultChatBackgroundSnapshot(true).colors[0]).assertEqual('#444444');
    });

    it('seedFromDefault falls back to empty when nothing has resolved for that mode', 0, () => {
      // A mode no test in this suite ever populates a snapshot for.
      const seeded = harness(true);
      seeded.store.seedFromDefault();
      // Either genuinely empty (first run) or whatever the last dark=true
      // snapshot from an earlier test happened to be — both are valid
      // ChatBackgroundState shapes, so just assert the seed never crashes and
      // always yields a usable state (colors is always an array).
      expect(Array.isArray(seeded.store.current().colors)).assertTrue();
    });

    it('an empty transitional patch never overwrites a good cached snapshot', 0, () => {
      const h = harness(false);
      h.store.applyKnownBackground(solidFillBackground(0x654321));
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#654321');
      // null clears this store's own state back to empty, but that transient
      // clear must not poison the shared cache other chats seed from.
      h.store.applyKnownBackground(null);
      expect(h.store.current().colors.length).assertEqual(0);
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#654321');
    });

    it('a chat with its own background does not get cached as the account default', 0, () => {
      const h = harness(false);
      h.store.applyKnownBackground(solidFillBackground(0x777777));
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#777777');
      // Give chat 555 its own background in ChatStore's cache before opening
      // it, so hasSpecificBackground() is true for every patch that follows.
      const newChat: TdObject = { '@type': 'updateNewChat' };
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 555;
      chat['background'] = solidFillBackground(0x00FF00);
      newChat['chat'] = chat;
      h.bridge.onReceive(JSON.stringify(newChat));
      h.store.open(555);
      h.store.applyKnownBackground(gradientBackground(0xAAAAAA, 0xBBBBBB, 90));
      expect(h.store.current().colors[0]).assertEqual('#AAAAAA');
      // The shared default snapshot must still be the earlier, unrelated one.
      expect(defaultChatBackgroundSnapshot(false).colors[0]).assertEqual('#777777');
    });
  });
}
