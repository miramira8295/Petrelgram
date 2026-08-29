import { fileIo } from '@kit.CoreFileKit';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from './ChatStore';
import { ChatThemeStore } from './ChatThemeStore';
import { fillColorsOf, objectOrNull } from '../util/backgroundPresentation';
import { inflateTgvIfNeeded } from '../util/gunzipTgs';
import {
  KEY_APP_BG_STATE_DARK, KEY_APP_BG_STATE_LIGHT,
  KEY_CHAT_BG_SNAP_DARK, KEY_CHAT_BG_SNAP_LIGHT, KEY_LOCAL_BG_DARK, KEY_LOCAL_BG_LIGHT, setString
} from './AppSettings';
import { localWallpaperWins } from '../util/localWallpaper';
import { logE, logI } from '../util/log';

// Everything the chat surface needs to paint its background. One immutable
// snapshot instead of the nine separate page state variables this replaces.
export interface ChatBackgroundState {
  custom: boolean;        // false = fall back to the app's chat_bg resource
  colors: string[];       // gradient fill, empty when the background is an image
  angle: number;          // gradient rotation, degrees
  path: string;           // local file once downloaded, '' while pending
  imageOpacity: number;   // pattern intensity, 1 for plain wallpapers
  dimming: number;        // 0..1, applied over the image in dark mode
  blurred: boolean;
  bubbleOutColor: string; // outgoing bubble tint carried by a chat theme
  // A pattern is a small tileable motif drawn over the fill; a photo wallpaper
  // is a single image that covers the surface. They need different fits, so the
  // renderer has to be able to tell them apart.
  isPattern: boolean;
}

const INSTALLED_DEFAULT_RETRIES: number = 2;
const INSTALLED_DEFAULT_RETRY_MS: number = 2500;

// TdObject 的 background → 我们的 ChatBackgroundState。
//
// 【为什么抽出来】APP 壁纸槽位选**原生壁纸**时要走同一段转换：那条路不经过本
// store（Telegram 协议里根本没有「APP 背景」这个概念，它只能是本机设置），但必须
// 得到**一模一样**的状态——否则同一张壁纸在聊天里和在主界面上会长得不一样。
//
// 返回里 state.path 恒为 ''：文档要异步下载，由调用方拿 file 自己去取。
// themeName 非空表示这是 backgroundTypeChatTheme，那条路要走主题解析而不是壁纸。
// state 为 null 表示这个 background 画不出任何东西（既没有填充也没有文档）。
export interface BackgroundStateResult {
  state: ChatBackgroundState | null;
  file: TdObject | null;
  fileId: number;
  typeName: string;
  themeName: string;
}

export function backgroundStateOf(chatBackground: TdObject): BackgroundStateResult {
  // Chat.background 是包着可复用 background 对象的 chatBackground；裸的
  // background 也接受，保持接口兼容。
  const nested = objectOrNull(chatBackground['background']);
  const background = nested !== null ? nested : chatBackground;
  const type = objectOrNull(background['type']);
  if (type === null) {
    return { state: null, file: null, fileId: 0, typeName: '', themeName: '' };
  }
  const typeName: string = (type['@type'] as string | undefined) ?? '';
  if (typeName === 'backgroundTypeChatTheme') {
    return {
      state: null, file: null, fileId: 0, typeName,
      themeName: (type['theme_name'] as string | undefined) ?? ''
    };
  }
  let fill: TdObject | null = null;
  let pattern: boolean = false;
  if (typeName === 'backgroundTypeFill' || typeName === 'backgroundTypePattern') {
    fill = objectOrNull(type['fill']);
    pattern = typeName === 'backgroundTypePattern';
  }
  const colors: string[] = fillColorsOf(fill);
  const angle: number = fill !== null
    ? ((fill['rotation_angle'] as number | undefined) ?? 180) : 180;
  const document = objectOrNull(background['document']);
  const file = document !== null ? objectOrNull(document['document']) : null;
  const fileId: number = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
  if (colors.length === 0 && fileId === 0) {
    return { state: null, file: null, fileId: 0, typeName, themeName: '' };
  }
  const dimming: number = Math.max(0, Math.min(
    1, ((chatBackground['dark_theme_dimming'] as number | undefined) ?? 0) / 100
  ));
  const blurred: boolean = typeName === 'backgroundTypeWallpaper' &&
    ((type['is_blurred'] as boolean | undefined) ?? false);
  let imageOpacity: number = 1;
  if (pattern) {
    const intensity: number = Math.abs((type['intensity'] as number | undefined) ?? 50);
    imageOpacity = Math.max(0.08, Math.min(1, intensity / 100));
  }
  return {
    state: {
      custom: true, colors, angle, path: '',
      imageOpacity, dimming, blurred, bubbleOutColor: '', isPattern: pattern
    },
    file, fileId, typeName, themeName: ''
  };
}

// 此刻仍被某个壁纸槽位引用着的本机图片路径。
//
// 上传过的壁纸是**共用的**：同一张图可以同时给多个槽位用，不必重传（用户要求）。
// 因此换图/移除时不能再无条件删旧文件——那张图可能正被别的槽位引用着。调用方拿这
// 份清单配合 util/localWallpaper.wallpaperFileStillUsed 判断，**先写入新值再判断**，
// 这样本槽位的旧引用已经解除、只剩别人的。
export function referencedWallpaperPaths(): string[] {
  const out: string[] = [];
  for (const key of [KEY_APP_BG_STATE_LIGHT, KEY_APP_BG_STATE_DARK]) {
    const st: ChatBackgroundState | null = parseSnapshot(AppStorage.get<string>(key) ?? '');
    if (st !== null && st.path !== '') {
      out.push(st.path);
    }
  }
  for (const key of [KEY_LOCAL_BG_LIGHT, KEY_LOCAL_BG_DARK]) {
    const p: string = AppStorage.get<string>(key) ?? '';
    if (p !== '') {
      out.push(p);
    }
  }
  return out;
}

export function emptyChatBackground(): ChatBackgroundState {
  return {
    custom: false, colors: [], angle: 180, path: '',
    imageOpacity: 1, dimming: 0, blurred: false, bubbleOutColor: '', isPattern: false
  };
}

// 本机自选壁纸画出来是什么样。
//
// **渲染和设置页的缩略图必须用同一个构造。**原来只有 applyDefault 里有这三行，
// 设置页的四行缩略图则只读了账号默认快照——用户给「聊天浅色/聊天深色」传了自己
// 的图之后，那两行的缩略图一直是空的（真机实报）。两处各写一遍必然跑偏，所以
// 收成一个函数。
//
// blurred 恒为真的理由见 applyDefault 里那段说明：本机图没有"壁纸自己的属性"，
// 它模不模糊完全由用户那根滑杆说了算。
export function localWallpaperState(path: string): ChatBackgroundState {
  return {
    custom: true, colors: [], angle: 180, path: path,
    imageOpacity: 1, dimming: 0, blurred: true, bubbleOutColor: '', isPattern: false
  };
}

type Listener = (state: ChatBackgroundState) => void;

// The last fully-resolved account-default background, remembered process-wide
// so a freshly opened ChatPage can seed its initial `chatBg` from it instead
// of `emptyChatBackground()`. Without this, every chat that resolves to the
// account default (the common case) starts one frame — really, however long
// the getChat/getInstalledBackgrounds round trip takes — on the empty state,
// whose `colors.length === 0` branch paints the near-white `chat_bg` resource
// in light mode. That's the white flash: not a rendering-layer bug, but the
// store's own `subscribe()` synchronously handing a brand-new ChatPage's
// listener the constructor's empty state before `open()` has had a chance to
// resolve anything real.
//
// Keyed by dark/light because the two modes usually resolve to different
// wallpapers; a stale wrong-mode snapshot would itself flash the wrong colors
// for a frame, which is why a mismatch just falls back to empty instead of
// serving the other mode's cache.
let lastDefaultSnapshot: ChatBackgroundState | null = null;
let lastDefaultIsDark: boolean = false;

// Only a state that actually carries something visible (a fill or a path) is
// worth caching — the transient "cleared" state some code paths patch through
// on their way to a real background would otherwise overwrite a good snapshot
// with an empty one and reintroduce exactly the flash this exists to avoid.
function rememberDefaultSnapshot(state: ChatBackgroundState, forDark: boolean): void {
  if (state.colors.length === 0 && state.path === '') {
    return;
  }
  lastDefaultSnapshot = state;
  lastDefaultIsDark = forDark;
  // 同时落盘：进程内的这一份只在本次启动内有效，而白屏恰恰发生在冷启动后
  // 的第一次进入——那时内存里还什么都没有。
  setString(forDark ? KEY_CHAT_BG_SNAP_DARK : KEY_CHAT_BG_SNAP_LIGHT,
    serialiseSnapshot(state));
}

// 手写序列化而不是 JSON：字段就这几个，且 colors 是字符串数组，用制表符分隔
// 比 JSON.parse 后逐字段做类型断言更直白，也不依赖 ArkTS 对 parse 结果的
// 类型处理。颜色值本身是 '#RRGGBB' 形式，不含分隔符。
export function serialiseSnapshot(s: ChatBackgroundState): string {
  return [
    s.colors.join(','), `${s.angle}`, s.path, `${s.imageOpacity}`,
    `${s.dimming}`, s.blurred ? '1' : '0', s.bubbleOutColor,
    s.isPattern ? '1' : '0', s.custom ? '1' : '0'
  ].join('\t');
}

export function parseSnapshot(raw: string): ChatBackgroundState | null {
  if (raw === '') {
    return null;
  }
  const f: string[] = raw.split('\t');
  if (f.length < 9) {
    return null;
  }
  const colors: string[] = f[0] === '' ? [] : f[0].split(',');
  // 空快照没有意义——它正是这套机制要避免的东西。
  if (colors.length === 0 && f[2] === '') {
    return null;
  }
  return {
    custom: f[8] === '1',
    colors,
    angle: Number.parseFloat(f[1]),
    path: f[2],
    imageOpacity: Number.parseFloat(f[3]),
    dimming: Number.parseFloat(f[4]),
    blurred: f[5] === '1',
    bubbleOutColor: f[6],
    isPattern: f[7] === '1'
  };
}

// 账号默认背景被改动时作废快照。设置页直接调 TDLib、不经过本 store，所以
// 改完背景不会触发 patch()/rememberDefaultSnapshot——盘上那份会一直是旧的。
// 不在这里"算出新快照"是因为设置页手里只有用户的选择，真正的 colors/path
// 要等 TDLib 解析回来；作废之后最坏退化成一次空种子（白一下），比拿旧快照
// 画出**错误的背景**要好。下一次打开会话时 patch() 会重新落一份正确的。
export function invalidateDefaultSnapshot(forDark: boolean): void {
  if (lastDefaultSnapshot !== null && lastDefaultIsDark === forDark) {
    lastDefaultSnapshot = null;
  }
  setString(forDark ? KEY_CHAT_BG_SNAP_DARK : KEY_CHAT_BG_SNAP_LIGHT, '');
}

// Returns the last known account-default snapshot for the given mode, or an
// empty background if none has resolved yet (first run) or the cached one is
// for the other color mode.
export function defaultChatBackgroundSnapshot(forDark: boolean): ChatBackgroundState {
  if (lastDefaultSnapshot !== null && lastDefaultIsDark === forDark) {
    return lastDefaultSnapshot;
  }
  // 冷启动：内存里还没有，回读上次落盘的那一份。命中后提到内存，后续
  // 每个会话都走上面那条快路径。
  const key: string = forDark ? KEY_CHAT_BG_SNAP_DARK : KEY_CHAT_BG_SNAP_LIGHT;
  const stored = parseSnapshot(AppStorage.get<string>(key) ?? '');
  if (stored !== null) {
    lastDefaultSnapshot = stored;
    lastDefaultIsDark = forDark;
    return stored;
  }
  return emptyChatBackground();
}

// Inflated .tgv → .svg, remembered for the process.
//

// Resolves the background for one open chat, following the same precedence the
// official client uses: the chat's own background → its theme's background →
// the account default → the installed default for the current light/dark mode.
//
// Extracted from ChatPage, where this logic sat as nine @State variables, four
// TDLib subscriptions wired into aboutToAppear, and a dozen private methods.
// `isDarkMode` is injected rather than read here because determining it needs a
// UI resource context, which a store has no business holding.
export class ChatBackgroundStore {
  private client: TdClient;
  private chats: ChatStore;
  private themes: ChatThemeStore;
  private isDarkMode: () => boolean;

  private chatId: number = 0;
  private state: ChatBackgroundState = emptyChatBackground();
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];

  // Guards async resolution against a newer one having started meanwhile.
  private resolveSeq: number = 0;
  // Last applied background, serialized — avoids re-running identical updates.
  private signature: string = '';
  private fileId: number = 0;

  constructor(client: TdClient, chats: ChatStore, themes: ChatThemeStore,
    isDarkMode: () => boolean) {
    this.client = client;
    this.chats = chats;
    this.themes = themes;
    this.isDarkMode = isDarkMode;
  }

  current(): ChatBackgroundState {
    return this.state;
  }

  // Seeds this store's initial state from the last known account-default
  // snapshot (see rememberDefaultSnapshot above), before the first
  // subscribe() call synchronously hands that state to the page. No emit —
  // there are no listeners yet, and open()/refresh() will patch a real
  // (possibly different) state in shortly after regardless. Call this before
  // subscribe(), only for a store that is about to open() the account default
  // (chatId 0, or a chat known to have no specific background/theme).
  seedFromDefault(): void {
    this.state = defaultChatBackgroundSnapshot(this.isDarkMode());
  }

  subscribe(listener: Listener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.state);
    return (): void => {
      this.listeners = this.listeners.filter((l: Listener): boolean => l !== listener);
    };
  }

  private emit(): void {
    for (const listener of this.listeners) {
      listener(this.state);
    }
  }

  private patch(next: ChatBackgroundState): void {
    this.state = next;
    // Only remember this as "the account default" when this chat has no
    // background/theme of its own — a chat-specific wallpaper isn't what most
    // other chats should be seeded with.
    if (!this.hasSpecificBackground()) {
      rememberDefaultSnapshot(next, this.isDarkMode());
    }
    this.emit();
  }

  // ArkTS forbids object spread (arkts-no-spread), so field-wise copy it is.
  private cloned(): ChatBackgroundState {
    return {
      custom: this.state.custom,
      colors: this.state.colors,
      angle: this.state.angle,
      path: this.state.path,
      imageOpacity: this.state.imageOpacity,
      dimming: this.state.dimming,
      blurred: this.state.blurred,
      bubbleOutColor: this.state.bubbleOutColor,
      isPattern: this.state.isPattern
    };
  }

  private patchBubbleColor(color: string): void {
    const next: ChatBackgroundState = this.cloned();
    next.bubbleOutColor = color;
    this.patch(next);
  }

  private patchPath(path: string): void {
    const next: ChatBackgroundState = this.cloned();
    next.path = path;
    this.patch(next);
  }

  open(chatId: number): void {
    this.close();
    this.chatId = chatId;
    this.unsubs = [
      this.client.onUpdate('updateChatBackground', (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) !== this.chatId) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const background = objectOrNull(u['background']);
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.applyDefault(seq);
        }
      }),
      this.client.onUpdate('updateChatTheme', (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) !== this.chatId) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const themeName: string = (u['theme_name'] as string | undefined) ?? '';
        if (themeName === '') {
          const specific = this.chats.entryOf(this.chatId)?.background ?? null;
          if (specific !== null) {
            this.applyBackground(specific);
          } else {
            this.applyDefault(seq);
          }
        } else {
          this.applyTheme(themeName, seq);
        }
      }),
      this.client.onUpdate('updateDefaultBackground', (u: TdObject): void => {
        const forDarkTheme: boolean = (u['for_dark_theme'] as boolean | undefined) ?? false;
        if (forDarkTheme !== this.isDarkMode() || this.hasSpecificBackground()) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const background = objectOrNull(u['background']);
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.loadInstalledDefault(forDarkTheme, seq);
        }
      }),
      this.client.onUpdate('updateFile', (u: TdObject): void => {
        const file = u['file'] as TdObject | undefined;
        if (file !== undefined) {
          this.applyFile(file);
        }
      })
    ];
    this.refresh();
  }

  close(): void {
    for (const unsub of this.unsubs) {
      unsub();
    }
    this.unsubs = [];
    this.resolveSeq++;
    this.signature = '';
    this.fileId = 0;
    this.chatId = 0;
  }

  refresh(): void {
    // Reset the theme bubble tint; the theme path re-derives it in the same
    // tick when this chat still carries a theme.
    this.patchBubbleColor('');
    const cached = this.chats.entryOf(this.chatId);
    if (cached?.background !== null && cached?.background !== undefined) {
      this.applyBackground(cached.background);
    }
    const seq: number = ++this.resolveSeq;
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.chatId;
    this.client.send(request).then((chat: TdObject): void => {
      if (seq !== this.resolveSeq) {
        return;
      }
      const background = objectOrNull(chat['background']);
      const themeName: string = (chat['theme_name'] as string | undefined) ?? '';
      if (background !== null || themeName === '') {
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.applyDefault(seq);
        }
      } else {
        this.applyTheme(themeName, seq);
      }
    }).catch((error: TdError): void => {
      logE(`ChatBackgroundStore getChat failed: ${error.message}`);
    });
  }

  // A background already carried by a cached ChatEntry — the page hands this in
  // when it refreshes header identity, saving a round trip.
  applyKnownBackground(background: TdObject | null): void {
    this.applyBackground(background);
  }

  private hasSpecificBackground(): boolean {
    const entry = this.chats.entryOf(this.chatId);
    return entry !== undefined && (entry.background !== null || entry.themeName !== '');
  }

  // The image for a background is always the full document.
  //
  // Patterns used to take the thumbnail instead, and that is what made them
  // render at the wrong scale: the thumbnail is a picker-sized raster of the
  // whole motif sheet, so stretching it across the screen scales the motif up by
  // whatever the viewport/thumbnail ratio happens to be. No objectFit fixes a
  // source that is already the wrong thing. The real document is a .tgv —
  // gzipped SVG — which inflateIfPattern() unpacks below; being a vector it
  // scales exactly.
  private documentFile(background: TdObject): TdObject | null {
    const document = objectOrNull(background['document']);
    if (document === null) {
      return null;
    }
    return objectOrNull(document['document']);
  }

  // Pattern documents arrive as .tgv (gzipped SVG), which ArkUI's Image cannot
  // read. Inflate once next to the download and hand back the .svg path; the
  // file is regenerated if TDLib's cache ever drops it.
  private async inflateIfPattern(path: string): Promise<string> {
    // 与 APP 壁纸槽位共用同一份实现，见 util/gunzipTgs。
    return inflateTgvIfNeeded(path);
  }

  private localPathOf(file: TdObject): string {
    const local = objectOrNull(file['local']);
    if (local === null ||
      !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
  }

  private applyFile(file: TdObject): void {
    const id: number = (file['id'] as number | undefined) ?? 0;
    if (id === 0 || id !== this.fileId) {
      return;
    }
    const path: string = this.localPathOf(file);
    if (path !== '' && path !== this.state.path) {
      this.usePath(path, id);
    }
  }

  // Inflation is async, so a background resolved in the meantime must win:
  // fileId is re-checked before the state is touched.
  private usePath(path: string, id: number): void {
    if (!path.endsWith('.tgv')) {
      this.patchPath(path);
      return;
    }
    this.inflateIfPattern(path).then((usable: string): void => {
      if (usable !== '' && id === this.fileId) {
        this.patchPath(usable);
      }
    });
  }

  private requestFile(file: TdObject): void {
    const id: number = (file['id'] as number | undefined) ?? 0;
    this.fileId = id;
    if (id <= 0) {
      return;
    }
    const localPath: string = this.localPathOf(file);
    if (localPath !== '') {
      logI(`[ChatBackground] chat=${this.chatId} file=${id} cached=true`);
      this.usePath(localPath, id);
      return;
    }
    logI(`[ChatBackground] chat=${this.chatId} file=${id} download=true`);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = id;
    request['priority'] = 1;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    this.client.send(request).then((downloaded: TdObject): void => {
      this.applyFile(downloaded);
    }).catch((error: TdError): void => {
      logE(`ChatBackgroundStore download ${id} failed: ${error.message}`);
    });
  }

  private applyBackground(chatBackground: TdObject | null): void {
    const signature: string =
      chatBackground !== null ? JSON.stringify(chatBackground) : 'none';
    if (signature === this.signature) {
      return;
    }
    this.signature = signature;
    this.fileId = 0;
    const bubbleOutColor: string = this.state.bubbleOutColor;
    const cleared: ChatBackgroundState = emptyChatBackground();
    cleared.bubbleOutColor = bubbleOutColor;
    this.patch(cleared);
    if (chatBackground === null) {
      return;
    }

    const parsed: BackgroundStateResult = backgroundStateOf(chatBackground);
    if (parsed.themeName !== '') {
      this.applyTheme(parsed.themeName, ++this.resolveSeq);
      return;
    }
    logI(
      `[ChatBackground] chat=${this.chatId} type=${parsed.typeName}` +
      ` colors=${parsed.state !== null ? parsed.state.colors.length : 0} file=${parsed.fileId}`
    );
    if (parsed.state === null) {
      return;
    }
    const next: ChatBackgroundState = parsed.state;
    next.bubbleOutColor = bubbleOutColor;
    this.patch(next);
    if (parsed.file !== null) {
      this.requestFile(parsed.file);
    }
  }

  // 本机自选壁纸的路径（'' = 没设）。深浅色各一张。
  private localWallpaperPath(forDarkTheme: boolean): string {
    return AppStorage.get<string>(forDarkTheme ? KEY_LOCAL_BG_DARK : KEY_LOCAL_BG_LIGHT) ?? '';
  }

  private applyDefault(seq: number): void {
    const forDarkTheme: boolean = this.isDarkMode();
    // 本机自选壁纸插在**账号默认背景之前**：那是用户在这台设备上明确挑的图，
    // 而账号默认多半是服务端下发或从别的端同步来的。会话自己的背景仍然更优先——
    // 走不到这里（applyBackground 已经处理），localWallpaperWins 里再挡一道，
    // 判据与完整推导见 util/localWallpaper。
    const local: string = this.localWallpaperPath(forDarkTheme);
    if (localWallpaperWins(this.hasSpecificBackground(), local)) {
      // blurred 对整图壁纸的含义就是"模糊滑杆对它生效"（见
      // util/chatBackgroundRaster.backgroundBlurRadius：非图案的整图要这个标志为真
      // 才吃 userBlur）。服务端壁纸的这一位是壁纸自己的属性，而本机自选的图没有
      // "自己的属性"——它的模糊完全由用户那根滑杆说了算，所以这里恒为 true。
      // 深色遮罩不用管：那是画在整层末尾的全局层，与壁纸来源无关，本来就生效。
      this.patch(localWallpaperState(local));
      return;
    }
    if (this.chats.defaultBackgroundKnown(forDarkTheme)) {
      const background = this.chats.defaultBackground(forDarkTheme);
      if (background !== null) {
        this.applyBackground(background);
        return;
      }
    }
    this.loadInstalledDefault(forDarkTheme, seq);
  }

  // 拉「已安装默认背景」失败（真机上是网络超时，切深色那一刻连续四次）时的处理：
  // **不清空**。原来 catch 里 applyBackground(null) 会把已经画好的状态打回空——
  // 用户看到的就是背景突然变成一片 #0E1621 平底，要重进会话才回来。
  // 现在：当前状态还在就留着；当前是空的就拿本地快照兜底；再有界重试两次。
  private loadInstalledDefault(forDarkTheme: boolean, seq: number, attempt: number = 0): void {
    const request: TdRequest = { '@type': 'getInstalledBackgrounds' };
    request['for_dark_theme'] = forDarkTheme;
    this.client.send(request).then((result: TdObject): void => {
      if (seq !== this.resolveSeq || this.hasSpecificBackground()) {
        return;
      }
      const backgrounds: TdObject[] = (result['backgrounds'] as TdObject[] | undefined) ?? [];
      const matchingDefaults = backgrounds.filter((item: TdObject): boolean =>
        ((item['is_default'] as boolean | undefined) ?? false) &&
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      const matchingTheme = backgrounds.filter((item: TdObject): boolean =>
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      // Never use an arbitrary background from the opposite color scheme. When
      // TDLib has no matching candidate the renderer keeps chat_bg.
      const selected = matchingDefaults.length > 0
        ? matchingDefaults[0] : (matchingTheme.length > 0 ? matchingTheme[0] : null);
      logI(
        `[ChatBackground] chat=${this.chatId} source=installed dark=${forDarkTheme} ` +
        `count=${backgrounds.length} defaults=${matchingDefaults.length}`
      );
      this.applyBackground(selected);
    }).catch((error: TdError): void => {
      logE(`ChatBackgroundStore getInstalledBackgrounds failed: ${error.message}`);
      if (seq !== this.resolveSeq) {
        return;
      }
      this.keepOrSeedDefault(forDarkTheme);
      if (attempt < INSTALLED_DEFAULT_RETRIES) {
        setTimeout((): void => {
          if (seq === this.resolveSeq && this.chatId !== 0 && !this.hasSpecificBackground()) {
            this.loadInstalledDefault(forDarkTheme, seq, attempt + 1);
          }
        }, INSTALLED_DEFAULT_RETRY_MS);
      }
    });
  }

  private keepOrSeedDefault(forDarkTheme: boolean): void {
    if (this.state.colors.length > 0 || this.state.path !== '') {
      logI(`[ChatBackground] chat=${this.chatId} installed default unavailable, keeping current`);
      return;
    }
    const snapshot: ChatBackgroundState = defaultChatBackgroundSnapshot(forDarkTheme);
    if (snapshot.colors.length === 0 && snapshot.path === '') {
      return;
    }
    snapshot.bubbleOutColor = this.state.bubbleOutColor;
    logI(`[ChatBackground] chat=${this.chatId} installed default unavailable, seeded from snapshot`);
    this.patch(snapshot);
  }

  // theme_name backgrounds live in TDLib's chat theme catalog rather than on
  // Chat.background. TDLib has no getChatThemes request — the list arrives once
  // per connection via updateChatThemes and is cached by ChatThemeStore.
  private applyTheme(themeName: string, seq: number): void {
    if (seq !== this.resolveSeq) {
      return;
    }
    const theme = this.themes.chatThemes().find((item: TdObject): boolean =>
      ((item['name'] as string | undefined) ?? '') === themeName
    );
    if (theme === undefined) {
      this.patchBubbleColor('');
      this.applyBackground(null);
      return;
    }
    const settingsName: string = this.isDarkMode() ? 'dark_settings' : 'light_settings';
    const settings = objectOrNull(theme[settingsName]);
    const bubbleColors: string[] = fillColorsOf(settings !== null
      ? objectOrNull(settings['outgoing_message_fill']) : null);
    this.patchBubbleColor(bubbleColors.length > 0 ? bubbleColors[0] : '');
    this.applyBackground(settings !== null ? objectOrNull(settings['background']) : null);
  }
}

// Resolve the account-default background once at startup so the first chat that
// opens finds the file downloaded and the pattern already inflated, instead of
// paying for both between the tap and the first frame.
//
// chatId 0 matches no chat, so the per-chat updates this store subscribes to
// never fire for it and it settles on the account default — exactly what most
// chats resolve to anyway. It is closed straight after; the work it warms lives
// in TDLib's file cache and in util/gunzipTgs 的解压缓存，两者都是进程级的。
export function preloadDefaultChatBackground(
  client: TdClient, chats: ChatStore, themes: ChatThemeStore, isDarkMode: () => boolean,
  onResolved: (state: ChatBackgroundState) => void = (): void => {}
): void {
  const store = new ChatBackgroundStore(client, chats, themes, isDarkMode);
  const unsub = store.subscribe((state: ChatBackgroundState): void => {
    // A pure-gradient background is fully resolved with no file at all, so
    // waiting for a path would leave those unrasterised forever.
    if (state.path !== '' || state.colors.length > 0) {
      unsub();
      store.close();
      onResolved(state);
    }
  });
  store.open(0);
}
