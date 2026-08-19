import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { gradientStops } from './backgroundPresentation';

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
const NO_BLUR_RADIUS: number = 0;
// Both the single-image wallpaper and the composited pattern grid need the
// same overscan when blurred, so the edges softened by the blur don't expose
// a rim of the layer underneath.
const BLUR_OVERSCAN_SCALE: number = 1.08;

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
function tileIndices(count: number): number[] {
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
  return `v6_${p.colors.join('-')}_${p.angle}_${p.path}_${p.isPattern ? 'p' : 'w'}` +
    `_${Math.round(p.imageOpacity * 100)}_${Math.round(p.dimming * 100)}` +
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
  try {
    if (fileIo.accessSync(dest)) {
      rasterCache.set(sig, dest);
      return dest;
    }
  } catch (e) {
    // 盘上没有或不可读都当作未命中，重新合成即可。
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
    packer = image.createImagePacker();
    const file = await fileIo.open(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      // Awaited before the PixelMap is released — releasing during an in-flight
      // encode crashes the process.
      await packer.packToFile(pixelMap, file.fd, { format: 'image/jpeg', quality: 96 });
    } finally {
      await fileIo.close(file);
    }
    rasterCache.set(sig, dest);
    return dest;
  } catch (e) {
    console.error(`rasterizeBackground failed: ${e}`);
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
