import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { gradientStops } from './backgroundPresentation';
import { logE, logI } from './log';

// Flatten the chat background into one opaque JPEG, once per (background, size).
//
// The live version is a stack: a linear-gradient Column, an Image on top of it
// (for a pattern that Image is a full-screen SVG, which is a lot of paths to
// rasterise), an opacity, an optional blur with an overscan scale, and a
// dimming Column. Every chat that opens builds that stack again, and it stays
// in the compositor underneath a scrolling List for as long as the chat is on
// screen.
//
// None of it is dynamic. Rendering it offscreen once and handing the result to
// a single Image gives the compositor one opaque bitmap instead, which is what
// the layered version was going to be resolved to anyway — just not once per
// frame, per chat.

export interface BackgroundRasterParams {
  colors: string[];
  angle: number;
  path: string;          // '' for a pure gradient
  isPattern: boolean;
  imageOpacity: number;
  dimming: number;
  blurred: boolean;
  userBlur: number;      // vp, user's blur-amount setting (KEY_BG_BLUR)
  width: number;         // vp
  height: number;        // vp
}

// Blur radii. A tiled pattern always gets softened; a real photo wallpaper
// keeps the pre-existing behaviour: sharp unless the account (or the user,
// synced from the official client) marked it `is_blurred`. A pure gradient
// has no texture to blur so there's nothing to do there. How much softening
// "should blur" actually applies is now the user's own call — the Chat
// Background page's slider (KEY_BG_BLUR in AppSettings.ets, default 8) — so
// the radius itself is a caller-supplied parameter, not a fixed constant.
export const NO_BLUR_RADIUS: number = 0;
// Both the single-image wallpaper and the composited pattern grid need the
// same overscan when blurred, so the edges softened by the blur don't expose
// a rim of the layer underneath.
export const BLUR_OVERSCAN_SCALE: number = 1.08;

// Pure function: given the shape of the background and the user's blur
// setting, decide how much blur (if any) the composited image should get.
// Returns a new value only — no mutation of the caller's params.
// 图案的实际不透明度 = 壁纸自带的 intensity × 用户设的浓度。
// 只作用于图案；整图壁纸的 imageOpacity 恒为 1，压低它会让整张图发灰。
export function patternOpacity(
  isPattern: boolean, imageOpacity: number, strength: number
): number {
  if (!isPattern) {
    return imageOpacity;
  }
  return Math.max(0.04, Math.min(1, imageOpacity * strength));
}

// Two successive black overlays can be flattened into one without changing
// the resulting pixels: 1 - (1 - base) * (1 - overlay).
export function combineDimming(base: number, overlay: number): number {
  const a: number = Math.max(0, Math.min(1, base));
  const b: number = Math.max(0, Math.min(1, overlay));
  return 1 - (1 - a) * (1 - b);
}

// 纯色 / 跟随系统（2026-09-27 用户定）：没有模糊和深色遮罩这两个选项。
// 纯色没有可模糊的内容；遮罩对纯色只是"换一个更深的颜色"，直接挑更深的色即可。
// 渐变保留遮罩（多色渐变压暗后观感不同于换色），图案 / 整图壁纸两者都保留。
export function wallpaperTakesBlur(path: string): boolean {
  return path !== '';
}

export function wallpaperTakesUserDim(colors: string[], path: string): boolean {
  return path !== '' || colors.length > 1;
}

export function backgroundBlurRadius(
  path: string, isPattern: boolean, blurred: boolean, userBlur: number
): number {
  if (path === '') {
    return NO_BLUR_RADIUS;
  }
  if (isPattern) {
    return userBlur;
  }
  return blurred ? userBlur : NO_BLUR_RADIUS;
}

// Whether the image needs the overscan that hides the soft edge a blur
// leaves behind. Tied to the same rule as the radius — any nonzero radius
// needs it.
function backgroundOverscan(p: BackgroundRasterParams): boolean {
  return backgroundBlurRadius(p.path, p.isPattern, p.blurred, p.userBlur) > NO_BLUR_RADIUS;
}

// Pattern tile geometry --------------------------------------------------
//
// A pattern document is a small repeatable motif sheet, not a standalone
// photo. The official client tiles it edge-to-edge at a fixed density
// instead of fitting one instance to the screen.
//
// The pattern SVG's native viewBox is 1440x2960 (confirmed by pulling the
// inflated .tgv off a device, see background-diagnosis-report.md — width:height
// ratio ~0.4865). ImageFit.Contain (the pre-tiling approach) is constrained by
// whichever axis is tighter; since the SVG is much taller than it is wide,
// that axis is always the canvas height, so a single Contain instance already
// matched the vertical motif density exactly — the only thing wrong with it
// was the bare strip left on the sides on any screen wider (relative to its
// height) than the pattern's own ratio.
//
// So the tile keeps that same vertical density instead of introducing a new
// one: tile height = canvas height (one row, never repeated vertically), and
// tile width follows from the SVG's own aspect ratio. Only the column COUNT
// changes with screen width, repeating sideways until the canvas is covered.
const PATTERN_SVG_WIDTH: number = 1440;
const PATTERN_SVG_HEIGHT: number = 2960;
const PATTERN_ASPECT: number = PATTERN_SVG_WIDTH / PATTERN_SVG_HEIGHT;

export interface PatternTileGrid {
  cols: number;
  rows: number;
  tileWidth: number;
  tileHeight: number;
}

// Pure function: given a canvas size, work out how many columns of a
// full-canvas-height, native-aspect-ratio tile are needed to cover the
// canvas width, rounding up so there is never a bare sliver on the sides
// (the grid is then centered and clipped to the canvas, so the overrun from
// rounding is trimmed symmetrically instead of showing as a gap on one
// side). Always exactly one row — the tile height already equals the canvas
// height, so vertical repetition would just waste draw calls.
export function patternTileGrid(width: number, height: number): PatternTileGrid {
  const safeWidth: number = Math.max(width, 1);
  const safeHeight: number = Math.max(height, 1);
  const tileHeight: number = safeHeight;
  const tileWidth: number = tileHeight * PATTERN_ASPECT;
  const cols: number = Math.max(1, Math.ceil(safeWidth / tileWidth));
  return { cols, rows: 1, tileWidth, tileHeight };
}

// [0, count) as a fresh array — ForEach needs a concrete array, not a range.
export function tileIndices(count: number): number[] {
  const result: number[] = [];
  for (let i = 0; i < count; i++) {
    result.push(i);
  }
  return result;
}

// Blur is applied once, to the whole composited grid below — never to the
// individual tile Images. Blurring each tile on its own would soften every
// tile's own edges independently, and adjacent tiles' independently-blurred
// edges don't line back up into a continuous motif: the seam between tiles
// would show as a faint blurred line. Blurring the assembled grid as a
// single layer instead treats the seams as interior pixels of one continuous
// image, so neighbouring tiles blur into each other exactly like the source
// artwork does — only the outer boundary of the whole grid (already handled
// by the existing overrun + Stack.clip(true) in backgroundLayer) needs the
// overscan.
// 只给离屏光栅用。它是多参数的全局 @Builder，建完就不跟随参数变化了（官方
// 《自定义构建函数》：多个参数时不支持 @Builder 函数内 UI 组件刷新），而快照
// 是一次性的，这里正好无所谓。实时绘制那一路必须用 PatternTileLayer 组件。
@Builder
export function patternTileGridLayer(
  path: string, opacity: number, grid: PatternTileGrid, blurRadius: number
) {
  Column() {
    ForEach(tileIndices(grid.rows), (r: number) => {
      Row() {
        ForEach(tileIndices(grid.cols), (c: number) => {
          Image(path.startsWith('/') ? `file://${path}` : path).draggable(false)
            .width(grid.tileWidth).height(grid.tileHeight)
            .objectFit(ImageFit.Cover)
            .autoResize(false)
            .interpolation(ImageInterpolation.High)
            .syncLoad(true);
        }, (c: number): string => `${r}_${c}`);
      }
      .width(grid.cols * grid.tileWidth).height(grid.tileHeight);
    }, (r: number): string => `${r}`);
  }
  .width(grid.cols * grid.tileWidth)
  .height(grid.rows * grid.tileHeight)
  .opacity(opacity)
  .scale(blurRadius > NO_BLUR_RADIUS
    ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
  .blur(blurRadius);
}

// sig -> file path. The file also survives on disk, but the map is what keeps
// the common case (every chat resolving to the account default) off the disk
// entirely.
const rasterCache: Map<string, string> = new Map();
const inFlight: Set<string> = new Set();
// Offline components are not on the tree, so nothing drives their build/layout
// and resource loading; the capture has to be given time for it. The guide's
// own example uses this order of magnitude.
const SNAPSHOT_DELAY_MS: number = 320;

export function rasterSignature(p: BackgroundRasterParams): string {
  // v7: dimming may now be the composition of the wallpaper's server value
  // and the user's dark-mode mask. Keep four decimal places so neighbouring
  // slider steps cannot alias to the same cached bitmap.
  //
  // v6: the blur radius that PATTERN_BLUR_RADIUS/WALLPAPER_BLURRED_RADIUS used
  // to hardcode is now the user's own KEY_BG_BLUR setting (ChatBackgroundPage's
  // slider) — the same colors/path/etc. can now composite to a different bitmap
  // purely because the user dragged the slider, so the version token has to
  // retire every raster the v5 pipeline ever cached, or dragging the slider
  // would keep serving the old blur from the map/disk cache.
  //
  // v5: pattern tiles are now full-canvas-height (one row, columns only)
  // instead of a fixed 340vp tile height, and patterns now carry a fixed
  // blur of their own (8) instead of always being sharp; photo wallpapers
  // are back to their original blurred-flag-only rule (0 or 12) instead of
  // the v3 always-8/16 baseline.
  //
  // v4: patterns are tiled instead of a single ImageFit.Contain instance.
  // v3: photo wallpapers always carried some blur instead of only the
  // blurred ones (superseded by v5 above).
  const radius: number = backgroundBlurRadius(p.path, p.isPattern, p.blurred, p.userBlur);
  return `v7_${p.colors.join('-')}_${p.angle}_${p.path}_${p.isPattern ? 'p' : 'w'}` +
    `_${Math.round(p.imageOpacity * 100)}_dim${Math.round(p.dimming * 10000)}` +
    `_blur${radius}_${Math.round(p.width)}x${Math.round(p.height)}`;
}

// 光栅图的文件名完全由签名决定（见 rasterizeBackground 里的 dest），所以上一次
// 启动写下的那张图，这一次启动本来就能直接用——但原来只查进程内的 Map，冷启动
// 必然未命中，于是首次进入聊天会用整整一秒渲染实时图层（渐变 + 一大堆平铺图块
// + 蒙层），真机 Profiler 上表现为 Render Service 单帧 46–65ms 的掉帧，而第二次
// 进入命中内存缓存、只画一张 JPEG 就完全不卡。
//
// 传入 cacheDir 时顺带查一次磁盘。命中就提到内存里，后续调用还是走 Map。
// accessSync 只是一次 stat，而调用点是背景状态变化（每次进聊天几次），不在每帧
// 路径上。只缓存命中结果：未命中不写进 Map，否则一张刚写好的图会被负缓存挡住。
export function cachedRaster(sig: string, cacheDir: string = ''): string {
  const known = rasterCache.get(sig);
  if (known !== undefined) {
    return known;
  }
  if (cacheDir === '') {
    return '';
  }
  const dest = rasterPathFor(sig, cacheDir);
  // 只判存在不够：TRUNC 写入失败留下的 0 字节/半截文件也"存在"，会被永久命中成空图。
  // rasterUsable 会校验 JPEG 完整性，坏文件当场删掉并让本次走重新合成。
  const usable: boolean = rasterUsable(dest);
  // 冷启动第一次查盘时顺手清一次历史垃圾（残留 .tmp、坏图、超额旧图）。
  scheduleSweep(cacheDir);
  if (usable) {
    rasterCache.set(sig, dest);
    return dest;
  }
  return '';
}

// 文件名的唯一定义，写入与查找共用，避免两处拼法漂移。
function rasterPathFor(sig: string, cacheDir: string): string {
  return `${cacheDir}/chatbg_${sig.replace(/[^A-Za-z0-9_-]/g, '')}.jpg`;
}

@Builder
function backgroundLayer(p: BackgroundRasterParams) {
  Stack() {
    if (p.colors.length > 0) {
      Column()
        .width(p.width).height(p.height)
        .linearGradient({ angle: p.angle, colors: gradientStops(p.colors) });
    } else {
      Column().width(p.width).height(p.height).backgroundColor($r('app.color.chat_bg'));
    }
    if (p.path !== '' && p.isPattern) {
      // Tiled, not a single Contain instance — see the comment above
      // patternTileGrid(). Blur (and its overscan) is applied inside
      // patternTileGridLayer to the whole assembled grid, not per tile —
      // see the comment on that function for why.
      patternTileGridLayer(
        p.path, p.imageOpacity, patternTileGrid(p.width, p.height),
        backgroundBlurRadius(p.path, p.isPattern, p.blurred, p.userBlur));
    } else if (p.path !== '') {
      // Blur softens the edges into the layer underneath, so anything blurred
      // needs the overscan or a faint rim of the gradient/dimming shows through.
      Image(p.path.startsWith('/') ? `file://${p.path}` : p.path).draggable(false)
        .width(p.width).height(p.height)
        .objectFit(ImageFit.Cover)
        .opacity(p.imageOpacity)
        .scale(backgroundOverscan(p)
          ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
        .blur(backgroundBlurRadius(p.path, p.isPattern, p.blurred, p.userBlur))
        // 关闭降采样解码：offline 树里 autoResize 会按布局估算把 1157×2560 的
        // 源图解到约一半（实测 652×1443），快照再放大回全屏——用户看到的
        // "背景比实时版糊"就是这个。全分辨率解码 + 高质量插值。
        .autoResize(false)
        .interpolation(ImageInterpolation.High)
        // Offline components decode images on an IO thread by default, so the
        // snapshot would catch the gradient with a hole where the pattern goes.
        .syncLoad(true);
    }
    if (p.dimming > 0) {
      Column().width(p.width).height(p.height)
        .backgroundColor(Color.Black).opacity(p.dimming);
    }
  }
  .width(p.width).height(p.height)
  // The tile grid's width/height is rounded up to a whole number of tiles
  // and is centered by the Stack's default alignment, so it typically
  // overruns the canvas a little on every edge — clip it back to size
  // instead of letting it push the layer's bounds out.
  .clip(true);
}

// Returns the cached path immediately when there is one, otherwise renders,
// encodes and caches. Returns '' on any failure so the caller keeps the live
// layered rendering — this is an optimisation, never a requirement.
export async function rasterizeBackground(
  ui: UIContext, p: BackgroundRasterParams, cacheDir: string
): Promise<string> {
  const sig = rasterSignature(p);
  const hit = rasterCache.get(sig);
  if (hit !== undefined) {
    return hit;
  }
  if (p.width <= 0 || p.height <= 0 || inFlight.has(sig)) {
    return '';
  }
  inFlight.add(sig);
  let pixelMap: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    // ComponentContent + wrapBuilder, not a bare arrow calling the @Builder.
    // A global @Builder invoked outside a struct has no component context and
    // throws "Cannot read property observeComponentCreation2 of undefined" —
    // which this function then swallowed, so every chat silently kept the slow
    // layered rendering and the whole optimisation was dead code.
    //
    // The delay gives the offline tree time to build, lay out and load its
    // image; waitUntilRenderFinished makes the capture wait for the draw
    // commands rather than grabbing the previous frame. scale 1 keeps the
    // bitmap at screen size — the guide warns that oversized captures are both
    // wasteful and liable to fail outright.
    const node: ComponentContent<BackgroundRasterParams> =
      new ComponentContent(ui, wrapBuilder(backgroundLayer), p);
    pixelMap = await ui.getComponentSnapshot()
      .createFromComponent(node, SNAPSHOT_DELAY_MS, true,
        { scale: 1, waitUntilRenderFinished: true });
    const dest = rasterPathFor(sig, cacheDir);
    // 不再直接 TRUNC 正式文件：先写 .tmp，校验完整后再提交。
    // 这样正式名字下只会出现内容完整的图；写入失败/进程被杀只留下 .tmp 残留，
    // 由 sweepChatbgCache 清理，绝不会被 cachedRaster 命中。
    const tmp: string = dest + CHATBG_TMP_SUFFIX;
    packer = image.createImagePacker();
    rasterWriting.add(dest);
    try {
      // Awaited before the PixelMap is released — releasing during an in-flight
      // encode crashes the process.
      await writeRasterTmp(packer, pixelMap, tmp);
    } catch (e) {
      rasterWriting.delete(dest);
      try {
        fileIo.unlinkSync(tmp);
      } catch (e2) {
        // 没有残留就算了。
      }
      throw e as Error;
    }
    rasterWriting.delete(dest);
    if (!publishRaster(tmp, dest, cacheDir)) {
      return '';
    }
    rasterCache.set(sig, dest);
    return dest;
  } catch (e) {
    logE(`rasterizeBackground failed: ${e}`);
    return '';
  } finally {
    inFlight.delete(sig);
    if (packer !== undefined) {
      packer.release();
    }
    if (pixelMap !== undefined) {
      pixelMap.release();
    }
  }
}


// ── 图案预览的离屏光栅（设置页 WallpaperPreview 专用） ──────────────────────
//
// 和上面 rasterizeBackground 不是重复实现，两者的烘焙范围与失效条件都不一样：
//   · 这张只烘「图案本体」，不烘渐变、不烘蒙层 → 透明底 PNG，滑杆调浓度/模糊/
//     遮罩时位图不用重建，也就不会在拖动时反复重烘；
//   · 签名只含 path 与预览尺寸：图案本身没有深浅色，深浅两个槽位可以共享同一张；
//   · 用 PNG 无损：图案是矢量线稿 + 细星点，JPEG 的量化噪声会在边缘糊出一圈。
//
// 起因（真机 trace 2026-11-06）：聊天槽进入帧 177–179ms，其中 105ms 是
// `RSModifierManager Draw num:[180]` 里 10 条 `RSModifier::Draw` 各约 10ms ——
// PatternTileLayer 的 10 张 pattern.tgv.svg 每张都要在绘制时重新栅格化一次。
// 烘成一张位图后这块只剩一次 blit。

export interface PatternRasterParams {
  path: string;
  width: number;   // vp，与 PatternTileLayer 的 screenW 一致
  height: number;  // vp
}

// 只留最近几套：预览一次只显示一个背景，缓存跟着「最近用过的图案」走。
// 32 个图案全留会堆出上百 MB 的贴图，收益只有第二次点同一个图案。
const PATTERN_CACHE_MAX: number = 3;
const patternRasterCache: Map<string, string> = new Map();
const patternOrder: string[] = [];
const patternInFlight: Set<string> = new Set();

export function patternRasterSignature(p: PatternRasterParams): string {
  return `pat_v1_${p.path}_${Math.round(p.width)}x${Math.round(p.height)}`;
}

function patternRasterPathFor(sig: string, cacheDir: string): string {
  return `${cacheDir}/chatpat_${sig.replace(/[^A-Za-z0-9_-]/g, '')}.png`;
}

function rememberPatternRaster(sig: string, dest: string): void {
  patternRasterCache.set(sig, dest);
  const at: number = patternOrder.indexOf(sig);
  if (at >= 0) {
    patternOrder.splice(at, 1);
  }
  patternOrder.push(sig);
  while (patternOrder.length > PATTERN_CACHE_MAX) {
    const evicted: string = patternOrder[0];
    patternOrder.splice(0, 1);
    const gone: string | undefined = patternRasterCache.get(evicted);
    patternRasterCache.delete(evicted);
    if (gone !== undefined) {
      try {
        fileIo.unlinkSync(gone);
      } catch (e) {
        // 盘上已经没有（被系统清过 cache）就算了。
      }
    }
  }
}

// 与 cachedRaster 同构：先查进程内，再查磁盘（冷启动也要能命中上一次烘的那张）。
export function cachedPatternRaster(sig: string, cacheDir: string = ''): string {
  const known = patternRasterCache.get(sig);
  if (known !== undefined) {
    return known;
  }
  if (cacheDir === '') {
    return '';
  }
  const dest = patternRasterPathFor(sig, cacheDir);
  try {
    if (fileIo.accessSync(dest)) {
      rememberPatternRaster(sig, dest);
      return dest;
    }
  } catch (e) {
    // 未命中，重新烘。
  }
  return '';
}

// 透明底：只在画布上铺图案网格，不铺渐变、不铺蒙层。
@Builder
function patternOnlyLayer(p: PatternRasterParams) {
  Stack() {
    patternTileGridLayer(p.path, 1, patternTileGrid(p.width, p.height), NO_BLUR_RADIUS);
  }
  .width(p.width).height(p.height)
  .clip(true);
}

// 失败一律返回 ''，调用方回落到实时 PatternTileLayer —— 这是加速，不是前提。
export async function rasterizePattern(
  ui: UIContext, p: PatternRasterParams, cacheDir: string
): Promise<string> {
  const sig = patternRasterSignature(p);
  const hit = patternRasterCache.get(sig);
  if (hit !== undefined) {
    return hit;
  }
  if (p.path === '' || p.width <= 0 || p.height <= 0 || patternInFlight.has(sig)) {
    return '';
  }
  patternInFlight.add(sig);
  let pixelMap: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    // 与 rasterizeBackground 同样的三个前提：ComponentContent + wrapBuilder（全局
    // @Builder 在组件上下文外调用会抛 observeComponentCreation2）、留出时间让 SVG
    // 加载完、scale 1 保持 1:1 像素（放大既浪费又容易直接失败）。
    const node: ComponentContent<PatternRasterParams> =
      new ComponentContent(ui, wrapBuilder(patternOnlyLayer), p);
    pixelMap = await ui.getComponentSnapshot()
      .createFromComponent(node, SNAPSHOT_DELAY_MS, true,
        { scale: 1, waitUntilRenderFinished: true });
    const dest = patternRasterPathFor(sig, cacheDir);
    packer = image.createImagePacker();
    const file = await fileIo.open(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      // 先编码完再 release PixelMap，边编码边释放会把进程送掉。
      await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
    } finally {
      await fileIo.close(file);
    }
    rememberPatternRaster(sig, dest);
    logI(`[PatternRaster] baked ${sig}`);
    return dest;
  } catch (e) {
    logE(`rasterizePattern failed: ${e}`);
    return '';
  } finally {
    patternInFlight.delete(sig);
    if (packer !== undefined) {
      packer.release();
    }
    if (pixelMap !== undefined) {
      pixelMap.release();
    }
  }
}

// ── 背景 JPEG 缓存的磁盘生命周期 ─────────────────────────────────────────
//
// 为什么单独一节：快照编码原来直接以 TRUNC 打开正式文件再写。TRUNC 已经在 open
// 时把文件清零，packToFile 若中途失败（PixelMap 提前释放、编码器报错、进程被杀），
// 盘上就留下一张 0 字节或半截的 chatbg_*.jpg；而 cachedRaster 原来只做 accessSync
// （只判存在、不看内容），于是这张坏文件会被永久命中，CachedImage 解不出图 ——
// 壁纸消失且再也不会自愈。
//
// 本节把两件事变成不变量：
//   1) 正式文件名下只会出现「完整的 JPEG」（.tmp → 校验 → 提交）；
//   2) 回收只按 mtime 淘汰最旧，且绝不碰正在使用/正在写入的文件。
const CHATBG_PREFIX: string = 'chatbg_';
const CHATBG_SUFFIX: string = '.jpg';
const CHATBG_TMP_SUFFIX: string = '.tmp';
// 近 12 张有效缓存 ≈ 15–20MB（实测单张 1.45–1.74MB @1318x866）。
// 用户就在这些壁纸之间来回切，删早了每次都要重烘 320ms。
const CHATBG_KEEP_COUNT: number = 12;
const CHATBG_KEEP_BYTES: number = 24 * 1024 * 1024;
// 正常写入几秒内就会 rename 掉临时文件；活过 10 分钟的 .tmp 一律是异常退出的残留。
const CHATBG_STALE_TMP_MS: number = 10 * 60 * 1000;
const CHATBG_SWEEP_DEBOUNCE_MS: number = 1000;

// path -> 引用计数。谁在显示这一张，谁就 retain；页面下树 release。
const rasterRefs: Map<string, number> = new Map();
// 正在写（.tmp 已建、还没提交）的正式路径。清扫绝对不能碰它。
const rasterWriting: Set<string> = new Set();
const rasterSweepAt: Map<string, number> = new Map();

export function retainRaster(path: string): void {
  if (path === '') {
    return;
  }
  rasterRefs.set(path, (rasterRefs.get(path) ?? 0) + 1);
}

export function releaseRaster(path: string): void {
  if (path === '') {
    return;
  }
  const n: number = rasterRefs.get(path) ?? 0;
  if (n <= 1) {
    rasterRefs.delete(path);
  } else {
    rasterRefs.set(path, n - 1);
  }
}

// 磁盘文件被删后，进程内 sig -> path 的映射必须一起失效，
// 否则下一次会命中一个已经不存在的路径（Image 空白）。
function purgeRasterCachePath(path: string): void {
  const stale: string[] = [];
  for (const sig of rasterCache.keys()) {
    if (rasterCache.get(sig) === path) {
      stale.push(sig);
    }
  }
  for (const sig of stale) {
    rasterCache.delete(sig);
  }
}

// size>0 只是弱闸门：被截断的 JPEG 依然非空。再查 SOI(FFD8)/EOI(FFD9) 两端，
// 才能把「编码写到一半」和「完整图」区分开（SDK 对 packToFile 失败后 fd 里
// 剩下多少字节没有任何书面保证，只能靠内容自证）。
function rasterLooksCompleteJpeg(path: string): boolean {
  let file: fileIo.File | undefined = undefined;
  try {
    const st: fileIo.Stat = fileIo.statSync(path);
    if (st.isDirectory() || st.size < 4) {
      return false;
    }
    file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const head: ArrayBuffer = new ArrayBuffer(2);
    fileIo.readSync(file.fd, head, { offset: 0, length: 2 });
    const tail: ArrayBuffer = new ArrayBuffer(2);
    fileIo.readSync(file.fd, tail, { offset: st.size - 2, length: 2 });
    const h: Uint8Array = new Uint8Array(head);
    const t: Uint8Array = new Uint8Array(tail);
    return h[0] === 0xFF && h[1] === 0xD8 && t[0] === 0xFF && t[1] === 0xD9;
  } catch (e) {
    return false;
  } finally {
    if (file !== undefined) {
      try {
        fileIo.closeSync(file);
      } catch (e) {
        // ignore
      }
    }
  }
}

function rasterDrop(path: string, why: string): void {
  try {
    fileIo.unlinkSync(path);
    purgeRasterCachePath(path);
    logE(`[bgcache] drop ${why} path=${path}`);
  } catch (e) {
    // 删不掉（可能被别处占着）就只保证本次不命中。
  }
}

// 命中前的完整性校验：只认「存在且是完整 JPEG」。坏文件当场删掉，
// 让调用方走重新合成，而不是把一张坏图当成有效缓存永久复用。
function rasterUsable(path: string): boolean {
  try {
    const st: fileIo.Stat = fileIo.statSync(path);
    if (st.isDirectory() || st.size <= 0) {
      rasterDrop(path, `size=${st.size}`);
      return false;
    }
    if (!rasterLooksCompleteJpeg(path)) {
      rasterDrop(path, `incomplete jpeg size=${st.size}`);
      return false;
    }
    return true;
  } catch (e) {
    return false;
  }
}

// 正式提交：只有内容已经完整落在 .tmp 里才调用。
// 三级兜底 —— SDK 对 renameSync 覆盖已存在文件没有书面保证（只列了
// 13900015 File exists 这一个可能错误码），moveFileSync(mode=0) 才是 fs 里
// 文档明说「覆盖同名文件」的 API，最后才退到「先删目标再 rename」。
// 回滚性质：任何失败都只删 .tmp、不碰 dest，所以 dest 要么是旧的完整图，
// 要么不存在 —— 永远不会出现半截的正式文件。
function commitRaster(tmp: string, dest: string): void {
  try {
    fileIo.renameSync(tmp, dest);
    return;
  } catch (e) {
    logI(`[bgcache] rename failed, try moveFileSync: ${e}`);
  }
  try {
    fileIo.moveFileSync(tmp, dest, 0);
    return;
  } catch (e2) {
    logI(`[bgcache] moveFileSync failed, unlink then rename: ${e2}`);
  }
  try {
    fileIo.unlinkSync(dest);
  } catch (e3) {
    // 目标本来就不存在。
  }
  fileIo.renameSync(tmp, dest);
}

interface CachedRasterFile {
  path: string;
  size: number;
  mtime: number;
}

// 同步清扫：删残留 .tmp、删 0 字节/半截坏图、把数量与占用压到上限以内。
// 保护规则：正被页面引用（rasterRefs）、正在写入（rasterWriting）一律不删；
// 其余按 mtime 从旧到新淘汰。chatpat_*.png 由图案预览自己的 LRU 管，这里不越界。
export function sweepChatbgCache(cacheDir: string): void {
  if (cacheDir === '') {
    return;
  }
  let names: string[] = [];
  try {
    // listFileSync 返回的是「文件名」（非递归），不含目录前缀，所以要自己拼。
    names = fileIo.listFileSync(cacheDir);
  } catch (e) {
    logE(`[bgcache] list fail: ${e}`);
    return;
  }
  const now: number = Date.now();
  const kept: CachedRasterFile[] = [];
  let dropped: number = 0;
  for (const name of names) {
    const full: string = `${cacheDir}/${name}`;
    if (name.endsWith(CHATBG_TMP_SUFFIX)) {
      const dest: string = full.substring(0, full.length - CHATBG_TMP_SUFFIX.length);
      if (rasterWriting.has(dest)) {
        continue;
      }
      let stale: boolean = true;
      try {
        // Stat.mtime 单位是秒（SDK: "number of seconds elapsed since ..."）。
        stale = now - fileIo.statSync(full).mtime * 1000 > CHATBG_STALE_TMP_MS;
      } catch (e) {
        stale = true;
      }
      if (stale) {
        try {
          fileIo.unlinkSync(full);
          dropped++;
        } catch (e) {
          // 已经没了。
        }
      }
      continue;
    }
    if (!name.startsWith(CHATBG_PREFIX) || !name.endsWith(CHATBG_SUFFIX)) {
      continue;
    }
    let size: number = 0;
    let mtime: number = 0;
    try {
      const st: fileIo.Stat = fileIo.statSync(full);
      size = st.size;
      mtime = st.mtime;
    } catch (e) {
      continue;
    }
    if (size <= 0 || !rasterLooksCompleteJpeg(full)) {
      rasterDrop(full, `corrupt size=${size}`);
      dropped++;
      continue;
    }
    kept.push({ path: full, size, mtime });
  }
  kept.sort((a: CachedRasterFile, b: CachedRasterFile): number => b.mtime - a.mtime);
  let bytes: number = 0;
  for (let i = 0; i < kept.length; i++) {
    const f: CachedRasterFile = kept[i];
    bytes += f.size;
    const pinned: boolean = (rasterRefs.get(f.path) ?? 0) > 0 || rasterWriting.has(f.path);
    if (pinned) {
      continue;
    }
    if (i < CHATBG_KEEP_COUNT && bytes <= CHATBG_KEEP_BYTES) {
      continue;
    }
    try {
      fileIo.unlinkSync(f.path);
      purgeRasterCachePath(f.path);
      dropped++;
    } catch (e) {
      // 删不掉就下次再说。
    }
  }
  if (dropped > 0) {
    logI(`[bgcache] sweep dropped=${dropped} valid=${kept.length} bytes=${bytes} dir=${cacheDir}`);
  }
}

// 冷启动首次查盘与每次写入成功后各触发一次；节流合并，且延后到交互稳定后再跑，
// 避免在主题切换/滑杆拖动/列表滚动关键帧上做目录 I/O。
function scheduleSweep(cacheDir: string): void {
  if (cacheDir === '') {
    return;
  }
  const now: number = Date.now();
  const last: number = rasterSweepAt.get(cacheDir) ?? 0;
  if (now - last < CHATBG_SWEEP_DEBOUNCE_MS) {
    return;
  }
  rasterSweepAt.set(cacheDir, now);
  setTimeout((): void => {
    try {
      sweepChatbgCache(cacheDir);
    } catch (e) {
      logE(`[bgcache] sweep fail: ${e}`);
    }
  }, CHATBG_SWEEP_DEBOUNCE_MS);
}

export function sweepChatbgCacheSoon(cacheDir: string): void {
  scheduleSweep(cacheDir);
}

// 写 .tmp 的公共实现。调用方负责在失败时清理 .tmp。
async function writeRasterTmp(
  packer: image.ImagePacker, pixelMap: image.PixelMap, tmp: string
): Promise<void> {
  const file: fileIo.File = await fileIo.open(tmp,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    // 等编码完成再释放 PixelMap —— 编码中释放会崩进程（历史坑）。
    await packer.packToFile(pixelMap, file.fd, { format: 'image/jpeg', quality: 96 });
    try {
      fileIo.fsyncSync(file.fd);
    } catch (e) {
      // 老版本可能没有；close 也会刷。
    }
  } finally {
    await fileIo.close(file);
  }
}

// 供 rasterizeBackground 调用：把已经编码好的 .tmp 提交成正式缓存。
export function publishRaster(tmp: string, dest: string, cacheDir: string): boolean {
  try {
    const st: fileIo.Stat = fileIo.statSync(tmp);
    if (st.size <= 0 || !rasterLooksCompleteJpeg(tmp)) {
      logE(`[bgcache] refuse incomplete tmp size=${st.size}`);
      try {
        fileIo.unlinkSync(tmp);
      } catch (e) {
        // ignore
      }
      return false;
    }
  } catch (e) {
    return false;
  }
  try {
    commitRaster(tmp, dest);
  } catch (e) {
    logE(`[bgcache] commit fail: ${e}`);
    try {
      fileIo.unlinkSync(tmp);
    } catch (e2) {
      // ignore
    }
    return false;
  }
  scheduleSweep(cacheDir);
  return true;
}
