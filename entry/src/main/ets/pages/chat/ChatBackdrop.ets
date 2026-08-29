import { common } from '@kit.AbilityKit';
import { ChatBackgroundState } from '../../store/ChatBackgroundStore';
import { CachedImage } from '../common/CachedImage';
import {
  BackgroundRasterParams, backgroundBlurRadius, BLUR_OVERSCAN_SCALE, cachedRaster,
  NO_BLUR_RADIUS, patternOpacity, rasterSignature, rasterizeBackground
} from '../../util/chatBackgroundRaster';
import { PatternTileLayer } from './PatternTileLayer';
import { gradientStops } from '../../util/backgroundPresentation';
import {
  BG_BLUR_DEFAULT, BG_PATTERN_DEFAULT, CHAT_DIM_MAX, KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_EFFECT_BACKGROUND, KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_REDUCE_ANIM, powerAnimationDuration, powerFeatureEnabled, powerGroupAnimationDuration,
  powerGroupFeatureEnabled
} from '../../store/AppSettings';
import { KEY_APP_DARK } from '../../util/theme';
import { publishChatContentWidth } from '../../util/chatContentWidth';

// 聊天页的整层背景：壁纸 / 图案 / 渐变、两颗氛围光斑、粒子、深色遮罩。
//
// 从 ChatPage 里搬出来。它自成一体——**只吃输入、不向外回调**，所以搬家不需要
// 在两边之间牵任何状态：省电开关、模糊度、图案浓度、深色遮罩这些它自己从
// AppStorage 订阅，离屏光栅的缓存和防抖也一并搬了过来。
//
// 页面那边只剩三个入参：当前会话的背景状态和屏幕尺寸。

// 光栅防抖窗口。背景解析过程中会连续发布几个中间态（实测首次进入会话有三次
// 整屏 JPEG 编码，52+68+58ms），只有熬过安静窗口的那一个值得栅格化——期间
// 实时绘制的分层背景照常显示，视觉上不缺东西。
const RASTER_DEBOUNCE_MS: number = 280;
// 氛围光斑与粒子的相位周期。
const AMBIENT_PHASE_MS: number = 4200;

@Component
export struct ChatBackdrop {
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

  // 第一帧 onAreaChange 还没来，先按窗口尺寸；量到之后立即换成真值。
  private layerW(): number {
    return this.areaW > 0 ? this.areaW : this.screenW;
  }

  private layerH(): number {
    return this.areaH > 0 ? this.areaH : this.screenH;
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
  @Prop chatDim: number = 0;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) powerChatEffects: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_BACKGROUND) powerBackgroundEffect: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) powerParticles: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;

  @State private rasterPath: string = '';
  @State private phase: boolean = false;
  private rasterTimer: number = -1;
  private phaseTimer: number = -1;
  private readonly particleIds: number[] = [0, 1, 2, 3, 4, 5, 6, 7];

  aboutToAppear(): void {
    this.syncRaster();
    this.phaseTimer = setInterval((): void => {
      if (powerGroupFeatureEnabled(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND) ||
        powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.phase = !this.phase;
      } else {
        this.phase = false;
      }
    }, AMBIENT_PHASE_MS);
  }

  aboutToDisappear(): void {
    if (this.rasterTimer !== -1) {
      clearTimeout(this.rasterTimer);
      this.rasterTimer = -1;
    }
    if (this.phaseTimer !== -1) {
      clearInterval(this.phaseTimer);
      this.phaseTimer = -1;
    }
  }

  // 背景状态、屏幕尺寸、模糊度、图案浓度、深浅主题——任何一个变了，合成图都
  // 得重算，所以每一路都挂 @Watch。
  //
  // chatBg 尤其不能漏：@Prop 变化只触发**重新渲染**，不会重跑副作用。漏掉它
  // 时 syncRaster 只在 aboutToAppear 跑一次，而那时 bgStore 的订阅还没回调、
  // 拿到的是种子默认背景——真背景到达后光栅永不重算，轻则缓存全废、每次进
  // 会话都走实时分层绘制，重则一直停在默认背景的旧缓存图上，显示错壁纸。
  private onParamsChanged(): void {
    this.syncRaster();
    // 窗口变窄（悬浮小窗）时先把内容列宽压到窗口宽以内（issue #138）：内容列不可
    // 能比窗口宽，而 onAreaChange 那次精确的量要等布局回来；这期间气泡若还按
    // 旧的宽算 maxWidth，就会伸出右缘。窗口变宽时 min 取的仍是旧值、同值不写，
    // 等 onAreaChange 发精确值。
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

  private rasterParams(): BackgroundRasterParams {
    return {
      colors: this.chatBg.colors, angle: this.chatBg.angle, path: this.chatBg.path,
      isPattern: this.chatBg.isPattern,
      imageOpacity: this.imageOpacity(),
      dimming: this.chatBg.dimming, blurred: this.chatBg.blurred, userBlur: this.bgBlur,
      width: this.screenW, height: this.screenH
    };
  }

  private cacheDir(): string {
    return (getContext(this) as common.UIAbilityContext).cacheDir;
  }

  private syncRaster(): void {
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
    this.rasterShown = false;
    this.rasterPath = next;
  }

  private effectDuration(key: string, duration: number): number {
    if (this.reduceAnimations || !powerFeatureEnabled(KEY_POWER_SMOOTH_TRANSITIONS)) {
      return 0;
    }
    return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, key, duration);
  }

  // 自定义背景下不叠氛围效果：用户挑的图就是主角。
  private ambientEnabled(): boolean {
    return !this.chatBg.custom &&
      !this.powerSaving && this.powerChatEffects && this.powerBackgroundEffect;
  }

  private particlesEnabled(): boolean {
    return !this.chatBg.custom && !this.powerSaving && this.powerParticles;
  }

  // 深色下的黑色遮罩。放在整层的末尾而不是壁纸层里面，是为了一处覆盖三种情况：
  // 光栅缓存路径、实时绘制路径、以及上面那两颗氛围光斑。气泡和文字画在这整层
  // 之上，所以只压暗背景，不影响可读性。
  //
  // 也没有并进 chatBg.dimming：那个值是服务端按会话下发的（dark_theme_dimming），
  // 且已经烘进了光栅缓存的签名。把用户的这一份混进去会让每次调滑杆都作废整张
  // 缓存图，而单独一层是纯合成，不触发任何重新栅格化。
  private darkMaskOpacity(): number {
    if (!this.appDark) {
      return 0;
    }
    return Math.max(0, Math.min(CHAT_DIM_MAX, this.chatDim));
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
    Stack() {
      if (!this.rasterShown) {
      Stack() {
        if (this.chatBg.colors.length > 0) {
          Column()
            .width('100%').height('100%')
            .linearGradient({
              angle: this.chatBg.angle,
              colors: gradientStops(this.chatBg.colors)
            });
        } else {
          Column().width('100%').height('100%')
            .backgroundColor($r('app.color.chat_bg'));
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
      .width('100%').height('100%');
      }
      if (this.rasterPath !== '') {
      // 走 PixelMap 缓存，而不是 Image(file://…)。这张光栅是整屏 JPEG，解码约
      // 20ms——实测每次进会话都要重付一次，正是"第一次进卡、第二次顺"的主因。
      // 所有会话共用同一张背景，缓存后只解一次。
        CachedImage({
          path: this.rasterPath,
          boxWidth: this.layerW(),
          boxHeight: this.layerH(),
          radius: 0,
          fit: ImageFit.Cover,
          pin: true,
          onReady: (): void => { this.rasterShown = true; }
        });
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
      .onAreaChange((_old: Area, area: Area): void => {
        const w: number = area.width as number;
        const h: number = area.height as number;
        if (w > 0 && h > 0 && (w !== this.areaW || h !== this.areaH)) {
          this.areaW = w;
          this.areaH = h;
        }
        // 本层铺满聊天列，量到的宽就是内容列宽——气泡按它算宽度（issue #107），
        // 见 util/chatContentWidth。
        publishChatContentWidth(w);
      })
      // 平铺网格会向上取整到整数块并被 Stack 居中，通常四边都略微超出视口——
      // 裁回去，而不是让它把布局顶开。
      .clip(true);
  }

  build() {
    Stack() {
      this.wallpaperLayer();
      if (this.ambientEnabled()) {
        Circle({ width: 250, height: 250 })
          .fill('#142A9FE8')
          .position({ x: this.phase ? this.layerW() - 150 : -90, y: 110 })
          .opacity(this.phase ? 0.42 : 0.18)
          .animation({
            duration: this.effectDuration(KEY_POWER_EFFECT_BACKGROUND, AMBIENT_PHASE_MS),
            curve: Curve.EaseInOut
          });
        Circle({ width: 210, height: 210 })
          .fill('#1056C76F')
          .position({ x: this.phase ? -70 : this.layerW() - 130, y: 500 })
          .opacity(this.phase ? 0.16 : 0.36)
          .animation({
            duration: this.effectDuration(KEY_POWER_EFFECT_BACKGROUND, AMBIENT_PHASE_MS),
            curve: Curve.EaseInOut
          });
      }
      if (this.particlesEnabled()) {
        ForEach(this.particleIds, (id: number) => {
          Circle({ width: 3 + (id % 3), height: 3 + (id % 3) })
            .fill(id % 2 === 0 ? '#462A9FE8' : '#3D56C76F')
            .position({
              x: 22 + ((id * 67 + (this.phase ? 34 : 0)) % Math.max(40, this.layerW() - 44)),
              y: 120 + ((id * 151 + (this.phase ? 90 : 0)) % 650)
            })
            .opacity(this.phase ? 0.2 + (id % 3) * 0.12 : 0.48 - (id % 3) * 0.08)
            .animation({
              duration: powerAnimationDuration(KEY_POWER_PARTICLES, AMBIENT_PHASE_MS),
              curve: Curve.EaseInOut
            });
        }, (id: number): string => `power_particle_${id}`);
      }
      if (this.darkMaskOpacity() > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.darkMaskOpacity())
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
    .hitTestBehavior(HitTestMode.None);
  }
}
