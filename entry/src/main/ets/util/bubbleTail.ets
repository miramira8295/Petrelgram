// 气泡尾巴的三角裁剪。开着气泡材质时尾巴不能再是实色 Polygon（材质挂不到形状
// 上），改成一个 8×12 的小容器挂同一套材质，再按三角形裁掉——看上去就是气泡
// 延伸出来的一角。PathShape 的坐标是 px。
import { PathShape } from '@kit.ArkUI';
import { immersiveMaterialAvailable, overlayMaterial } from './overlayMaterial';
import { glassBubbleCommands } from './bubbleGlassPath';

export const TAIL_W: number = 8;
export const TAIL_H: number = 12;

export function tailClip(outgoing: boolean): PathShape {
  const w = vp2px(TAIL_W);
  const h = vp2px(TAIL_H);
  const commands = outgoing ? `M0 0 L${w} ${h} L0 ${h} Z` : `M${w} 0 L0 ${h} L${w} ${h} Z`;
  return new PathShape({ commands: commands });
}

// ---- 整块玻璃：尾巴 + 气泡包在一个容器里，材质挂容器、按整体轮廓裁剪 ----
//
// 一个修饰器同时管 systemMaterial 和 clipShape：ArkUI 一个节点只认一个
// attributeModifier，而 clipShape 又没法用普通属性按条件挂/摘。关掉时
// systemMaterial(undefined) 清材质、clip(false) 放开裁剪。
//
// **systemMaterial 这一句要单独按版本挡住**（materialModifier.ets 那一处是同款，
// 1.4.2 的登录后必崩就是它）。它是 API 26 才有的方法，低版本运行时里方法本身不
// 存在，取它就抛 `TypeError: undefined is not callable`——传 undefined 也一样，
// 因为炸在取方法那一步。
//
// 但**只跳过那一句**：clipShape / clip(false) / onAreaChange 在 API 20 上都在，
// 必须照常执行。整个 applyNormalAttribute 短路掉会让玻璃气泡在低版本上丢掉裁剪
// 和尺寸测量，渲染成没裁剪的直角矩形。

// 【尺寸回调**不在这里**注册，别再搬回来】
//
// 这里原来挂着一个 onMeasured：只在玻璃档注册 onAreaChange，动机是省掉每个气泡
// 一个常驻的 area-change 节点。**但写在 applyNormalAttribute 里就是错的**——
// 这个方法每次修饰器应用（每次复用、每次重渲染）都会跑，而
// `instance.onAreaChange(...)` 是**叠加注册，不是覆盖**。
//
// 2026-09-03 真机 trace：逐秒的 `HandleOnAreaChangeEvent_nodeCount` 峰值单调
// 只涨不落，会话开得越久，每帧要遍历的注册表越长。我按同一套写法又加了一个
// 条件注册的修饰器，增长率立刻从 3.3 节点/秒翻到 6.0，超时帧 3.8% → 10.5%。
//
// 现在尺寸回调改成挂在**属性链上**（声明式 `.onAreaChange`，每个节点只有一个），
// 代价是材质关掉时也注册着——但「一个节点注册一次」永远优于「一个节点注册 N 次」。
export class BubbleGlassModifier implements AttributeModifier<CommonAttribute> {
  private readonly live: boolean;
  private readonly path: PathShape | null;

  constructor(live: boolean, path: PathShape | null) {
    this.live = live;
    this.path = path;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    // 版本不够时一次都不碰 systemMaterial（连清除都不行），其余属性照常。
    const material: boolean = immersiveMaterialAvailable();
    if (!this.live) {
      if (material) {
        instance.systemMaterial(undefined);
      }
      instance.clip(false);
      return;
    }
    if (material) {
      // live 只跟气泡材质设置、可见区和省电策略有关，不跟滚动状态联动。滚动开始
      // 和结束都保持同一个材质实例，避免厚度/明暗档位切换造成闪动。
      instance.systemMaterial(overlayMaterial('bubble'));
    }
    if (this.path !== null) {
      instance.clipShape(this.path);
    }
  }
}

// 材质的高光边只沿节点自身的矩形边画；气泡左边缘（尾巴那侧）和尾巴自己的两条边
// 都是裁出来的内侧线，材质画不到。自己沿整条轮廓描一圈，颜色取接近材质高光的
// 半透明白。
export const GLASS_OUTLINE_COLOR: string = '#4DFFFFFF';
export const GLASS_OUTLINE_WIDTH: number = 1;

function radiusOf(v: Length | undefined): number {
  return typeof v === 'number' ? v : 0;
}

// w/h 是容器量到的 vp 尺寸；没量到（0）时不裁，先让材质按矩形出来。
// 整体轮廓的 path 命令（px）。裁剪走 inset=0，描边向内缩半个线宽——两者共用一条
// 轮廓时，线的外半边正好落在裁剪线外面被切掉，看着只有半根、还发虚。
// 轮廓 path 的键控缓存。
//
// 【为什么值得缓存】这条 path 只由九个标量决定，而它每次**重渲染**都要重算一遍：
// 09-03 的全相册录制里 `glassOutline` 归因到 462.6ms（cpuprofile，把 stateMgmt
// 的自耗时归给最近的应用帧之后排第二），而气泡的几何在两次重渲染之间**通常一个
// 字都没变**——同一行反复重渲染时算的是同一条 path。
//
// 一并省掉的还有 `vp2px(1)` 这个 NAPI 调用：命中缓存时连它都不用进。
//
// 上限 256：一屏几十行、每行两条（描边一条、裁剪一条），几个屏幕的量级足够；
// 满了就整体清空而不是 LRU——气泡宽高是跟着内容走的离散值，命中率对淘汰策略
// 不敏感，而整体清空的实现不会在热路径上多花一次 Map 遍历。
const OUTLINE_CACHE_MAX: number = 256;
const outlineCache: Map<string, string> = new Map<string, string>();

function outlineCommands(w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses, inset: number): string {
  const tl: number = radiusOf(radii.topLeft);
  const tr: number = radiusOf(radii.topRight);
  const br: number = radiusOf(radii.bottomRight);
  const bl: number = radiusOf(radii.bottomLeft);
  const key: string = `${w}|${h}|${outgoing ? 1 : 0}|${hasTail ? 1 : 0}` +
    `|${tl}|${tr}|${br}|${bl}|${inset}`;
  const hit: string | undefined = outlineCache.get(key);
  if (hit !== undefined) {
    return hit;
  }
  const commands: string = glassBubbleCommands(w, h, outgoing, hasTail,
    tl, tr, br, bl, TAIL_W, TAIL_H, vp2px(1), inset);
  if (outlineCache.size >= OUTLINE_CACHE_MAX) {
    outlineCache.clear();
  }
  outlineCache.set(key, commands);
  return commands;
}

// 屏幕密度变了（折叠屏展开、外接显示器）之后缓存里的 path 就不再对——
// vp2px(1) 没进键，所以必须由外部在这种时刻清一次。
export function clearOutlineCache(): void {
  outlineCache.clear();
}

// 描边用（向内缩半个线宽）。
export function glassOutlineCommands(w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses): string {
  return outlineCommands(w, h, outgoing, hasTail, radii, GLASS_OUTLINE_WIDTH / 2);
}

export function bubbleGlassModifier(live: boolean, w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses): BubbleGlassModifier {
  if (!live || w <= 0 || h <= 0) {
    return new BubbleGlassModifier(live, null);
  }
  return new BubbleGlassModifier(true,
    new PathShape({ commands: outlineCommands(w, h, outgoing, hasTail, radii, 0) }));
}
