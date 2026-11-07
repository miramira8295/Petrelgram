import { mediaThumbWidth } from '../../util/mediaBox';
import { setInlinePhotoTargetPx } from '../../util/formatMsgContent';
import { common } from '@kit.AbilityKit';
import { ChatBackgroundState } from '../../store/ChatBackgroundStore';
import {
  KEY_HEIGHT_BREAKPOINT, KEY_WIDTH_BREAKPOINT, KEY_WINDOW_PORTRAIT, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { KEY_APP_BG_ON, KEY_FORCE_SINGLE_COLUMN } from '../../store/AppSettings';
import { KEY_SPLIT_UNIFIED_BG } from '../../util/localWallpaper';
import { CachedImage } from '../common/CachedImage';
import { cachedPixelMap, loadPixelMap, PixelHandle, PixelRequest } from '../../util/pixelCache';
import { releaseAllWallpaperPins, releaseWallpaperPin, retainWallpaperPin } from '../../util/wallpaperPins';
import {
  BackgroundRasterParams, backgroundBlurRadius, BLUR_OVERSCAN_SCALE, cachedRaster, combineDimming,
  NO_BLUR_RADIUS, patternOpacity, rasterSignature, rasterizeBackground, retainRaster, releaseRaster,
  sweepChatbgCacheSoon, wallpaperTakesUserDim
} from '../../util/chatBackgroundRaster';
import { PatternTileLayer } from './PatternTileLayer';
import { gradientStops } from '../../util/backgroundPresentation';
import {
  BG_BLUR_DEFAULT, BG_PATTERN_DEFAULT, CHAT_DIM_MAX
} from '../../store/AppSettings';
import { KEY_APP_DARK } from '../../util/theme';
import { publishChatContentWidth } from '../../util/chatContentWidth';
import { logI } from '../../util/log';

// 每层背景一个稳定 owner id：同一张像素被多层/多页共享时各自记账，退出只还自己那份。
let backdropPinSeq: number = 0;

// 聊天页的整层背景：壁纸 / 图案 / 渐变、深色遮罩。
//
// 2026-10-30：原来还有两颗按相位时钟漂移的氛围光斑（「聊天背景动态效果」这个
// 省电开关的产物）。聊天页的用户反馈和之前会话详情页一样——「背景有个透明圆
// 来回动」——装饰撤掉，连带相位时钟、动效时长、那三组省电订阅一起删，别留
// 一堆只为它存在的空转字段。省电设置里对应的那一行也一并去掉。
//
// 从 ChatPage 里搬出来。它自成一体——**只吃输入、不向外回调**，所以搬家不需要
// 在两边之间牵任何状态：深浅主题它自己从 AppStorage 订阅，模糊度、图案浓度、
// 深色遮罩由调用方传入，离屏光栅的缓存和防抖也一并搬了过来。
//
// 页面传入背景参数与屏幕尺寸。

// 光栅防抖窗口。背景解析过程中会连续发布几个中间态（实测首次进入会话有三次
// 整屏 JPEG 编码，52+68+58ms），只有熬过安静窗口的那一个值得栅格化——期间
// 实时绘制的分层背景照常显示，视觉上不缺东西。
const RASTER_DEBOUNCE_MS: number = 280;

@Component
export struct ChatBackdrop {
  // 分栏 + 统一背景时，聊天页不再画自己的壁纸（否则会把整窗那张盖掉）。
  // 只有聊天页这一处传 true；AppBackdrop 用同一个组件画 APP 壁纸，那处保持 false。
  @Prop isChatSlot: boolean = false;
  // 页面级激活态：由 ChatPage 的 NavDestination.onShown / onHidden 驱动。
  //
  // 为什么还要这一路：onVisibleAreaChange 能覆盖"被另一层盖住"，但分栏退回列表时
  // 右栏依旧算在可见组合里，回调不报 ratio=0（真机实测），于是聊天层那张整屏光栅
  // 会一直钉着。这一路直接把"这一页现在是否真的在屏上"告诉背景层。
  @Prop @Watch('onActiveChanged') active: boolean = true;
  @StorageProp(KEY_SPLIT_UNIFIED_BG) private unifiedBg: boolean = true;
  @StorageProp(KEY_APP_BG_ON) private appBgOn: boolean = false;
  @StorageProp(KEY_WIDTH_BREAKPOINT) private widthBp: number = 1;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) private heightBp: number = 2;
  @StorageProp(KEY_WINDOW_PORTRAIT) private portrait: boolean = true;
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) private forceSingle: boolean = false;

  // 分栏且本会话没有自己的壁纸（跟随系统/纯色）时，底色跟左栏对齐。
  private splitNoWallpaper(): boolean {
    const split: boolean = isSplitByBreakpoint(
      this.widthBp, this.heightBp, this.forceSingle, this.portrait);
    return split && this.chatBg.path === '' && this.chatBg.colors.length === 0;
  }

  private suppressedByUnifiedBg(): boolean {
    // 【2026-11-05 真机实测：这条链是坏的，先停用】
    //
    // 原设计：分栏 + 统一背景 + APP 壁纸开启时，把聊天页这一层整个藏掉
    // （build() 末尾 opacity(0)），让挂在 MainScreen 上的 APP 壁纸透上来，两栏共用一张。
    //
    // 平板实测日志：`[Backdrop] branch suppressed=true split=true unified=true appBgOn=true
    // path=set pattern=true colors=4 raster=set shown=true` —— 背景解析、图案解压、
    // 光栅生成、CachedImage 解码（`cachedReady shown=true`）全都成功，**只有整层被藏掉**。
    // 而 APP 壁纸只铺在左栏，聊天列底下没有垫东西，于是聊天页永远白屏（用户报的正是这个）。
    // 手机不分栏，`isSplitByBreakpoint` 为 false，本来就走不到这里，故本改动对手机零影响。
    //
    // 恢复条件：APP 壁纸层改挂到窗口根、真正铺满两栏之后，再把下面这几行放回来。
    //   if (!this.isChatSlot || !this.unifiedBg || !this.appBgOn) { return false; }
    //   return isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingle, this.portrait);
    if (!this.isChatSlot || !this.unifiedBg || !this.appBgOn) {
      return false;
    }
    return false;
  }

  @Prop @Watch('onParamsChanged') chatBg: ChatBackgroundState;
  @Prop @Watch('onParamsChanged') screenW: number;
  @Prop @Watch('onParamsChanged') screenH: number;
  // 本层自己量到的尺寸。**壁纸盒子不能按 screenW/screenH 铺**：那两个是窗口
  // 尺寸，分栏之后本层只有右栏那么宽。按窗口宽铺出来的 Image 在这个 Stack
  // 里居中，两边各溢出 (窗宽−右栏宽)/2——左边那一截压进左栏，根节点的
  // clip(true) 只裁画面不裁触摸，于是左栏右半边全部点不动、滑不动
  // （issue #108），标题栏最右端的搜索键也在死区里（issue #109）。平板实测
  // 死区深度 240vp / 280vp，与 (1440−960)/2、(1440−880)/2 严丝合缝。
  // 光栅本身仍按窗口尺寸画（所有会话共用一张，Cover 裁掉即可）。
  // 光栅是否已经真正上屏。**不是 rasterPath !== ''**：路径有了不等于像素到了，
  // 解码走共享队列，离线 + 整会话翻译那种全屏重建风暴能把它挤到失败（issue #90），
  // 失败后 CachedImage 画的是空。分层实时绘制版在它变 true 之前一直垫在底下。
  @State private rasterShown: boolean = false;
  @State private areaW: number = 0;
  @State private areaH: number = 0;

  // 第一帧 onSizeChange 还没来，先按窗口尺寸；量到之后立即换成真值。
  private layerW(): number {
    return this.areaW > 0 ? this.areaW : this.screenW;
  }

  // 壁纸高度始终锚定完整窗口高度，不随软键盘 RESIZE 收缩而缩小重排，避免调起键盘时背景跟着往上蹿。
  private layerH(): number {
    return Math.max(this.areaH, this.screenH);
  }

  // ── 三根滑杆：由**调用方按槽位传入**，不再自己读全局键 ────────────────────
  //
  // 原来这三个值是从 KEY_BG_BLUR / KEY_BG_PATTERN(_DARK) / KEY_CHAT_DIM 直接读的，
  // 那等于「全 app 只有一套壁纸参数」。壁纸设置改成四个独立槽位（APP 浅色 /
  // APP 深色 / 聊天浅色 / 聊天深色）之后，每个槽位都要有自己的纹理、遮罩和模糊，
  // 所以这层不能再自己去拿——它画的是哪个槽位，只有调用方知道。
  //
  // 深浅色的选择也一并上交：本组件仍然订阅 appDark（暗化层要用），但"该拿浅色
  // 那份还是深色那份参数"是槽位的事，不是它的事。
  @Prop @Watch('onParamsChanged') bgBlur: number = BG_BLUR_DEFAULT;
  @Prop @Watch('onParamsChanged') bgPattern: number = BG_PATTERN_DEFAULT;
  @StorageProp(KEY_APP_DARK) @Watch('onParamsChanged') appDark: boolean = false;
  @Prop @Watch('onParamsChanged') chatDim: number = 0;
  @State private rasterPath: string = '';
  private rasterTimer: number = -1;
  // 本层在像素缓存里钉住的整屏光栅句柄。退出时只还自己这一份引用；
  // 同一槽位（bg:app / bg:chat）只留一张，切换时旧的排 2 秒宽限期释放。
  private pinHandle: PixelHandle | undefined = undefined;
  // 组件是否还活着：异步解码回来时用它判断还要不要钉。
  private pinAlive: boolean = false;
  // 本层在 pin 记账里的 owner id（退场时只摘自己这一份）。
  private pinOwner: string = '';
  // 当前 pin 对应的 pixelCache key（路径 + 像素尺寸）；尺寸变了要重钉。
  private pinKey: string = '';
  // 组件级代次：异步解码回来时比对，旧一轮的 then 不许动新一轮的引用。
  private pinGen: number = 0;
  // 白屏定位用：只在"分支组合"变化时打一条，避免每帧刷屏。确认修复后删掉。
  private diagLast: string = '';

  aboutToAppear(): void {
    this.pinAlive = true;
    this.pinOwner = 'bd#' + (++backdropPinSeq);
    this.diagDump();
    this.syncRaster();
  }

  aboutToDisappear(): void {
    this.pinAlive = false;
    if (this.rasterTimer !== -1) {
      clearTimeout(this.rasterTimer);
      this.rasterTimer = -1;
    }
    // 页面不在了就不再保护这张文件；文件本身仍在（最近 12 张保留），
    // 下次进来照样命中，只是允许清扫在超额时淘汰它。
    if (this.rasterPath !== '') {
      releaseRaster(this.rasterPath);
    }
    // 只放掉本层这一份引用：同一张图若还被别的层（分栏另一栏、主屏 APP 层）持有，
    // 记账里仍有 owner，最后一个人离开才进 2 秒宽限期；宽限期内切回来即取消释放，
    // 不必重解码。pinGen 自增让所有挂起中的解码回调作废。
    this.pinGen++;
    this.dropPin();
    releaseAllWallpaperPins(this.pinOwner);
    sweepChatbgCacheSoon(this.cacheDir());
  }

  // 背景状态、屏幕尺寸、模糊度、图案浓度、深浅主题——任何一个变了，合成图都
  // 得重算，所以每一路都挂 @Watch。
  //
  // chatBg 尤其不能漏：@Prop 变化只触发**重新渲染**，不会重跑副作用。漏掉它
  // 时 syncRaster 只在 aboutToAppear 跑一次，而那时 bgStore 的订阅还没回调、
  // 拿到的是种子默认背景——真背景到达后光栅永不重算，轻则缓存全废、每次进
  // 会话都走实时分层绘制，重则一直停在默认背景的旧缓存图上，显示错壁纸。
  private onParamsChanged(): void {
    this.diagDump();
    if (this.screenH > 0 && this.areaH > this.screenH) {
      this.areaH = this.screenH;
    }
    this.syncRaster();
    // 窗口变窄（悬浮小窗）时先把内容列宽压到窗口宽以内（issue #138）：内容列不可
    // 能比窗口宽，而 onSizeChange 那次精确的量要等布局回来；这期间气泡若还按
    // 旧的宽算 maxWidth，就会伸出右缘。窗口变宽时 min 取的仍是旧值、同值不写，
    // 等 onSizeChange 发精确值。
    publishChatContentWidth(Math.min(this.layerW(), this.screenW));
  }

  private patternStrength(): number {
    return this.bgPattern;
  }

  private blurRadius(): number {
    return backgroundBlurRadius(
      this.chatBg.path, this.chatBg.isPattern, this.chatBg.blurred, this.bgBlur);
  }

  private imageOpacity(): number {
    return patternOpacity(this.chatBg.isPattern, this.chatBg.imageOpacity, this.patternStrength());
  }

  // 氛围光斑撤掉之后，壁纸之上不再有实时装饰层，用户遮罩可以一直烘进光栅，
  // 省掉那层整屏合成。函数留着而不是直接写 true：下面两处调用点是同一个判据，
  // 将来若再引入实时装饰层，改这里一处就够。
  private canBakeDarkMask(): boolean {
    return true;
  }

  private rasterDimming(): number {
    return combineDimming(this.chatBg.dimming,
      this.canBakeDarkMask() ? this.darkMaskOpacity() : 0);
  }

  private rasterParams(): BackgroundRasterParams {
    return {
      colors: this.chatBg.colors, angle: this.chatBg.angle, path: this.chatBg.path,
      isPattern: this.chatBg.isPattern,
      imageOpacity: this.imageOpacity(),
      dimming: this.rasterDimming(), blurred: this.chatBg.blurred, userBlur: this.bgBlur,
      width: this.screenW, height: this.screenH
    };
  }

  private cacheDir(): string {
    return (getContext(this) as common.UIAbilityContext).cacheDir;
  }

  private syncRaster(): void {
    logI(`[Backdrop] sync path='${this.chatBg.path}' pattern=${this.chatBg.isPattern}` +
      ` colors=${this.chatBg.colors.length} blur=${this.bgBlur} raster='${this.rasterPath}'` +
      ` shown=${this.rasterShown} layer=${this.layerW()}x${this.layerH()}`);
    // 「跟随系统」（没有颜色也没有文件）不走光栅：底色是 $r('app.color.chat_bg')，
    // 离屏合成时按**那一刻**的深浅色取值，而签名里没有深浅色——深色下烘出的那张
    // 会被亮色模式原样命中，整页变黑（2026-09-27 真机）。一层纯色本来也不值得光栅。
    if (this.chatBg.colors.length === 0 && this.chatBg.path === '') {
      if (this.rasterTimer !== -1) {
        clearTimeout(this.rasterTimer);
        this.rasterTimer = -1;
      }
      this.setRasterPath('');
      return;
    }
    const sig = rasterSignature(this.rasterParams());
    const hit = cachedRaster(sig, this.cacheDir());
    if (hit !== '') {
      this.setRasterPath(hit);
      return;
    }
    // 先把旧图丢掉：一边留着上一张一边编码新图，会短暂显示错误会话的壁纸。
    this.setRasterPath('');
    if (this.rasterTimer !== -1) {
      clearTimeout(this.rasterTimer);
    }
    this.rasterTimer = setTimeout((): void => {
      this.rasterTimer = -1;
      const settled = this.rasterParams();
      const settledSig = rasterSignature(settled);
      const settledHit = cachedRaster(settledSig, this.cacheDir());
      if (settledHit !== '') {
        this.setRasterPath(settledHit);
        return;
      }
      rasterizeBackground(this.getUIContext(), settled, this.cacheDir())
        .then((path: string): void => {
          // 编码期间背景还可能再变一次，落盘前对一次签名。
          if (path !== '' && rasterSignature(this.rasterParams()) === settledSig) {
            this.setRasterPath(path);
          }
        });
    }, RASTER_DEBOUNCE_MS);
  }

  // 换光栅路径时兜底层要先回来：CachedImage 换源那一刻会先把旧像素撤掉、等新的
  // 解出来，中间那段和"解码失败"看起来一样，都是空。
  private setRasterPath(next: string): void {
    if (next === this.rasterPath) {
      return;
    }
    // 位图已经解码在内存里（这张整屏光栅 pin 住、所有会话共用）就直接算"已上屏"：CachedImage 首帧会同步命中
    // （start() 的 cachedPixelMap 分支），分层实时版（渐变 + SVG 图案平铺 + 模糊）一次都不必建（2026-09-15）。
    // 原来一律先置 false：每次进会话第一帧都把 SVG 图案铺一遍，等 onReady 再撤——转场第一帧 RS 要把这些路径
    // 画进整页离屏缓存，实测 85ms（trace 20260915T174809：UpdateCacheSurface + PATH_MASK_CACHE ×11）。
    // 请求尺寸必须和 CachedImage.request() 逐位一致（同一个 layerW/layerH、同一个 vp2px），否则 key 对不上。
    this.rasterShown = next !== '' && cachedPixelMap({
      path: next,
      width: vp2px(this.layerW()),
      height: vp2px(this.layerH()),
      // 壁纸保留完整色深；预查格式必须与下面 CachedImage 一致。
      opaque: false
    }) !== undefined;
    // 引用登记：清扫按 mtime 淘汰，正在显示的这一张必须被保护，
    // 否则换壁纸后立刻清扫就可能把它删掉、返回列表再进来又要重烘。
    if (this.rasterPath !== '' && this.rasterPath !== next) {
      releaseRaster(this.rasterPath);
    }
    this.rasterPath = next;
    if (next !== '') {
      retainRaster(next);
    }
    // 像素缓存槽位：先把旧的那张排队释放（2 秒宽限期，期间切回来会作废），
    // 再把新图钉住。请求参数必须与上面的同步预查、下面的 CachedImage 逐位一致，
    // 否则拿到的是另一把 key，钉住的和显示的不是同一张。
    this.dropPin();
    if (next !== '') {
      this.pinForSlot(next);
    }
    logI(`[Backdrop] setRaster next='${next}' shown=${this.rasterShown}`);
  }

  // 把当前这张光栅登记到本层名下。命中缓存直接登记；没命中就先解码再登记——
  // 这里主动 loadPixelMap 与 CachedImage 内部走同一个 key，后者会命中同一个句柄，
  // 不会重复解码。
  private pinForSlot(path: string): void {
    // 布局尺寸还没量到时不钉：layerW/H 这时回落到窗口尺寸，会先钉一张"错尺寸"的
    // 光栅，紧接着 onSizeChange 又要换真尺寸。真机实测那会多出一条 parked 条目，
    // 还会被 parked cap 挤出刚被复用那一张。等 onSizeChange → syncPin 一步到位。
    if (this.areaW <= 0) {
      return;
    }
    const req: PixelRequest = {
      path: path,
      width: vp2px(this.layerW()),
      height: vp2px(this.layerH()),
      opaque: false
    };
    const hit: PixelHandle | undefined = cachedPixelMap(req);
    if (hit !== undefined) {
      this.applyPin(hit, req);
      return;
    }
    const gen: number = this.pinGen;
    loadPixelMap(req).then((handle: PixelHandle | undefined): void => {
      // 解码回来时这一层可能已经换图/换尺寸/销毁了：只有同一轮请求才登记。
      if (handle === undefined || !this.pinAlive || gen !== this.pinGen) {
        return;
      }
      if (this.rasterPath !== path) {
        return;
      }
      this.applyPin(handle, req);
    }).catch((): void => {
      // 解码失败就走实时分层兜底，不登记即可。
    });
  }

  // pixelCache 的 key 口径（util/pixelCacheKey.ets）：路径 + 四舍五入后的像素尺寸。
  // 这里只需要"尺寸变没变"，不必拼 opaque。
  private pinKeyOf(req: PixelRequest): string {
    return `${req.path}@${Math.round(req.width)}x${Math.round(req.height)}`;
  }

  // 记下本层持有这一份像素。重复登记同一 key 直接早退；
  // 换图/换尺寸时先把旧的还掉，再登记新的。
  private applyPin(handle: PixelHandle, req: PixelRequest): void {
    const key: string = this.pinKeyOf(req);
    if (this.pinHandle === handle && this.pinKey === key) {
      return;
    }
    this.dropPin();
    this.pinHandle = handle;
    this.pinKey = key;
    retainWallpaperPin(handle, this.pinOwner);
  }

  // 还掉本层这一份引用；真正松钉发生在最后一个 owner 离开后的 2 秒宽限期。
  private dropPin(): void {
    if (this.pinHandle !== undefined) {
      releaseWallpaperPin(this.pinHandle, this.pinOwner);
      this.pinHandle = undefined;
    }
    this.pinKey = '';
  }

  // 尺寸变化（首帧 onSizeChange、分栏拖动、旋转）后 pixelCache key 会变：
  // 必须重钉，否则钉住的是旧尺寸的位图，新尺寸那份没有任何 LRU 保护。
  private syncPin(): void {
    if (this.rasterPath === '' || !this.pinAlive) {
      return;
    }
    const want: string = `${this.rasterPath}@${Math.round(vp2px(this.layerW()))}x${Math.round(vp2px(this.layerH()))}`;
    if (want === this.pinKey) {
      return;
    }
    this.pinForSlot(this.rasterPath);
  }

  // 页面被盖住（回列表 / 切到别的 tab / 分栏另一焦点）时，可见比例会掉到 0。
  // 这时把本层这份 pin 还掉，让位给真正在显示的那一层；重新可见时再登记回来。
  // 2 秒宽限期保证"划一下立刻回来"不会重解码。
  // 页面显示/隐藏（NavDestination 层给的强信号）。释放同样走 2 秒宽限期：
  // 退列表后立刻回来时 dropPin 只是把 owner 摘掉，宽限期内重新 retain 即取消释放。
  private onActiveChanged(): void {
    if (this.active) {
      if (this.rasterPath !== '' && this.pinAlive) {
        this.pinForSlot(this.rasterPath);
      }
      return;
    }
    this.pinGen++;
    this.dropPin();
  }

  private onVisibleChanged(isVisible: boolean, ratio: number): void {
    if (!isVisible || ratio <= 0) {
      this.pinGen++;
      this.dropPin();
      return;
    }
    if (this.rasterPath !== '' && this.pinAlive) {
      this.pinForSlot(this.rasterPath);
    }
  }

  // 深色下的用户遮罩。它会与服务端下发的 dark_theme_dimming 合并并烘进最终
  // 光栅；缓存生成期间仍由实时层兜底。
  private darkMaskOpacity(): number {
    // 纯色 / 跟随系统没有遮罩选项（见 wallpaperTakesUserDim），滑杆里留着的旧值不生效。
    if (!this.appDark || !wallpaperTakesUserDim(this.chatBg.colors, this.chatBg.path)) {
      return 0;
    }
    return Math.max(0, Math.min(CHAT_DIM_MAX, this.chatDim));
  }

  private liveDarkMaskOpacity(): number {
    const opacity: number = this.darkMaskOpacity();
    if (opacity <= 0) {
      return 0;
    }
    // The layered fallback has not baked the user's mask. Remove this node
    // only after the matching cached image has actually decoded on screen.
    return this.canBakeDarkMask() && this.rasterShown ? 0 : opacity;
  }

  // 白屏定位：把「走哪一支」的全部判据串成一行。任何一个变化才打，平静时不出日志。
  private diagDump(): void {
    const split: boolean = isSplitByBreakpoint(
      this.widthBp, this.heightBp, this.forceSingle, this.portrait);
    const line: string = `suppressed=${this.suppressedByUnifiedBg()} split=${split}`
      + ` unified=${this.unifiedBg} appBgOn=${this.appBgOn}`
      + ` path=${this.chatBg.path === '' ? 'empty' : 'set'}`
      + ` pattern=${this.chatBg.isPattern} colors=${this.chatBg.colors.length}`
      + ` raster=${this.rasterPath === '' ? 'none' : 'set'} shown=${this.rasterShown}`
      + ` layer=${this.layerW()}x${this.layerH()}`;
    if (line !== this.diagLast) {
      this.diagLast = line;
      logI(`[Backdrop] branch ${line}`);
    }
  }

  @Builder
  wallpaperLayer() {
    // 两层叠放，不再 if/else 互斥。
    //
    // 原来是「有光栅就只画 CachedImage，否则才画分层版」：光栅路径一有，分层版
    // 就从树上摘掉，而 CachedImage 解码失败时画的是空、不重试也不回退——背景
    // 就永久空白，直到退出重进会话。离线 + 整会话翻译正好把解码队列压满
    // （6 路 translate 同时 20s 超时 → 整屏行同时翻「失败」重建 → 一堆头像和
    // 缩略图解码，光栅那张全屏 JPEG 最大最容易被挤掉），用户报的就是这个
    // （issue #90）。现在分层版一直垫在底下，直到光栅像素真正上屏才撤。
    Stack({ alignContent: Alignment.TopStart }) {
      if (!this.rasterShown) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.chatBg.colors.length > 0) {
          Column()
            .width('100%').height('100%')
            .linearGradient({
              angle: this.chatBg.angle,
              colors: gradientStops(this.chatBg.colors)
            });
        } else {
          Column().width('100%').height('100%')
            // 分栏下没有壁纸时用 page_bg：左栏列表的底色就是它，两边同色
            // 才像「一片画布」；chat_bg 比它略白，中间那条缝看得出来。
            .backgroundColor(this.suppressedByUnifiedBg() || this.splitNoWallpaper()
              ? $r('app.color.page_bg') : $r('app.color.chat_bg'));
        }
        // 图案是可重复的小母题，不是独立照片：官方端按固定密度平铺到边，而不是
        // 把一份实例适配到屏幕（见 patternTileGrid 的注释——用 Contain 适配一份
        // 时，比例比图案更宽的设备（如平板）会在离轴边缘露白）。整图壁纸仍然
        // 铺满并裁切（Cover）。
        if (this.chatBg.path !== '' && this.chatBg.isPattern) {
          // 组件而不是全局 @Builder：多参数的全局 @Builder 建完就不再跟随参数
          // 变化，模糊度/图案浓度到货后这一层会停在旧值上。见 PatternTileLayer。
          PatternTileLayer({
            path: this.chatBg.path,
            tileOpacity: this.imageOpacity(),
            blurRadius: this.blurRadius(),
            screenW: this.layerW(),
            screenH: this.layerH()
          });
        } else if (this.chatBg.path !== '') {
          Image(this.chatBg.path.startsWith('/')
            ? `file://${this.chatBg.path}` : this.chatBg.path).draggable(false)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
            .opacity(this.imageOpacity())
            // 模糊需要一点过扫：否则边缘的半透明像素会在视口四周露出来。按
            // **实际半径**判断而不是 blurred 标志——用户把滑杆拖到 0 时不该白白
            // 放大裁掉边缘。
            .scale(this.blurRadius() > NO_BLUR_RADIUS
              ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
            .blur(this.blurRadius());
        }
        if (this.chatBg.dimming > 0) {
          Column().width('100%').height('100%')
            .backgroundColor(Color.Black)
            .opacity(this.chatBg.dimming);
        }
      }
      .width(this.layerW()).height(this.layerH());
      }
      if (this.rasterPath !== '') {
      // 走 PixelMap 缓存，而不是 Image(file://…)。这张光栅是整屏 JPEG，解码约
      // 20ms——实测每次进会话都要重付一次，正是"第一次进卡、第二次顺"的主因。
      // 所有会话共用同一张背景，缓存后只解一次。
        CachedImage({ spec: {
          path: this.rasterPath,
          boxWidth: this.layerW(),
          boxHeight: this.layerH(),
          radius: 0,
          fit: ImageFit.Cover,
          // 不再用 spec.pin 的永久 pin：整屏光栅的 pin 由 util/wallpaperPins 按槽位
          // 管理（切换/退出后 2 秒释放，重进可取消）。这里保持普通引用即可，
          // 组件销毁时 CachedImage 自己会还掉这一份。
          pin: false,
          // 渐变壁纸不能降到 RGB_565，否则会出现明显色带（#232 / #234）。
          // 与 setRasterPath 的缓存预查保持同一格式，继续复用整屏位图。
          opaque: false
        }, onReady: (): void => {
          this.rasterShown = true;
          logI('[Backdrop] cachedReady shown=true');
        } });
      }
    }
    .width('100%').height('100%')
    // 尽量把背景铺进键盘区。RESIZE 下 expandSafeArea 对向下扩展只做到一半
      // （官方《安全区域》：[KEYBOARD]+[BOTTOM] 不生效），但这已经够用——抽屉
      // 是齐边铺满的，铺不到的那一截正好被抽屉盖住，看不见。
      //
      // 另外两条路都实测更差：背景改固定高度会把扩展方向限制成只剩向上；
      // 切 OFFSET 虽然能让 expandSafeArea 完全生效，但整页上抬会把背景顶出屏幕。
      // SYSTEM 和 KEYBOARD 必须**分两次调用**：合在一个数组里时 BOTTOM 方向
      // 的扩展会失效（上面注释里"[KEYBOARD]+[BOTTOM] 不生效"的真身），底部
      // 安全区那一截铺不进去——深色模式下输入条下面就是一道窗口底色的黑边。
      .expandSafeArea([SafeAreaType.SYSTEM])
      .expandSafeArea([SafeAreaType.KEYBOARD])
      .hitTestBehavior(HitTestMode.None)
      // 量本层尺寸，见 areaW 的说明。同值不写：分栏拖动/键盘会连着来几次。
      // **必须挂在这层常驻的外层上**：曾经挂在分层版那个 Stack 上，光栅一到那支
      // 就下树，尺寸和内容列宽从此不再更新——#108 的修复只是碰巧赶在光栅落地前
      // 量过一次才成立。
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        const w: Length | undefined = size.width;
        const h: Length | undefined = size.height;
        if (typeof w !== 'number' || typeof h !== 'number') { return; }
        if (w > 0 && w !== this.areaW) {
          this.areaW = w;
        }
        // 软键盘 RESIZE 会把容器高度压小，不能把压小后的高度写回 areaH，否则壁纸会跟着键盘重排上移。
        const fullH: number = Math.max(this.areaH, h);
        if (fullH > 0 && fullH !== this.areaH) {
          this.areaH = fullH;
        }
        // 本层铺满聊天列，量到的宽就是内容列宽——气泡按它算宽度（issue #107），
        // 见 util/chatContentWidth。
        publishChatContentWidth(w);
        // Choose a source large enough for the widest media bubble in this
        // column; the pixel cache still decodes to each row's exact box size.
        if (w > 0) { setInlinePhotoTargetPx(vp2px(mediaThumbWidth(w, 0))); }
        // 尺寸变了 pixelCache key 也变：把 pin 跟到新尺寸上（同尺寸则不动作）。
        this.syncPin();
      })
      // 平铺网格会向上取整到整数块并被 Stack 居中，通常四边都略微超出视口——
      // 裁回去，而不是让它把布局顶开。
      .clip(true)
      // 可见性变化驱动 pin 的持/放：被盖住就还、露出来就再登记。
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number): void => {
        this.onVisibleChanged(isVisible, currentRatio);
      });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.wallpaperLayer();
      if (this.liveDarkMaskOpacity() > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.liveDarkMaskOpacity())
          .hitTestBehavior(HitTestMode.None);
      }
    }
    .width('100%').height('100%')
    // 整层背景必须自己铺进安全区。ChatPage 的根 Stack 没有 expandSafeArea
    // （只有里面那层内容 Column 有），所以背景作为它的孩子默认停在安全区
    // 边界，状态栏那一条就露出窗口底色——深色下是 #17212B 压在壁纸上，一条
    // 明显的分界（issue #7）。
    //
    // 原来只有下面实时绘制那一支带了 expandSafeArea，光栅那一支（缓存命中的
    // 常态路径）没带，于是同一个页面时好时坏。挂在这一层，两条路一起覆盖。
    .expandSafeArea([SafeAreaType.SYSTEM])
    .expandSafeArea([SafeAreaType.KEYBOARD])
    // 分栏 + 统一背景：整层透明，把位置让给 MainScreen 底下那张 APP 壁纸。
    // 用 opacity 而不是条件渲染，是为了不改变这层既有的布局与安全区展开行为。
    .opacity(this.suppressedByUnifiedBg() ? 0 : 1)
    .hitTestBehavior(HitTestMode.None);
  }
}
