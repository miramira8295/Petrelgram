// 气泡尾巴的三角裁剪。开着气泡材质时尾巴不能再是实色 Polygon（材质挂不到形状
// 上），改成一个 8×12 的小容器挂同一套材质，再按三角形裁掉——看上去就是气泡
// 延伸出来的一角。PathShape 的坐标是 px。
import { PathShape } from '@kit.ArkUI';
import { overlayMaterial } from './overlayMaterial';
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

export class BubbleGlassModifier implements AttributeModifier<CommonAttribute> {
  private readonly live: boolean;
  private readonly path: PathShape | null;
  // 尺寸回调只在玻璃档挂：关掉材质时整条 onAreaChange 根本不注册，
  // 省掉每个气泡一个常驻的 area-change 节点（真机 trace：峰值 102 个节点、
  // 全程 447ms 都花在 HandleOnAreaChangeEvent 上）。
  private readonly onMeasured: ((w: number, h: number) => void) | null;

  constructor(live: boolean, path: PathShape | null,
    onMeasured: ((w: number, h: number) => void) | null) {
    this.live = live;
    this.path = path;
    this.onMeasured = onMeasured;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (!this.live) {
      instance.systemMaterial(undefined);
      instance.clip(false);
      return;
    }
    instance.systemMaterial(overlayMaterial('bubble'));
    if (this.path !== null) {
      instance.clipShape(this.path);
    }
    if (this.onMeasured !== null) {
      const cb = this.onMeasured;
      instance.onAreaChange((_old: Area, area: Area): void => {
        cb(Number(area.width), Number(area.height));
      });
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
function outlineCommands(w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses, inset: number): string {
  return glassBubbleCommands(w, h, outgoing, hasTail,
    radiusOf(radii.topLeft), radiusOf(radii.topRight), radiusOf(radii.bottomRight), radiusOf(radii.bottomLeft),
    TAIL_W, TAIL_H, vp2px(1), inset);
}

// 描边用（向内缩半个线宽）。
export function glassOutlineCommands(w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses): string {
  return outlineCommands(w, h, outgoing, hasTail, radii, GLASS_OUTLINE_WIDTH / 2);
}

export function bubbleGlassModifier(live: boolean, w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses,
  onMeasured: ((w: number, h: number) => void) | null = null): BubbleGlassModifier {
  if (!live || w <= 0 || h <= 0) {
    return new BubbleGlassModifier(live, null, onMeasured);
  }
  return new BubbleGlassModifier(true,
    new PathShape({ commands: outlineCommands(w, h, outgoing, hasTail, radii, 0) }), onMeasured);
}
