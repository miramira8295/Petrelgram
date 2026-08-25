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

  constructor(live: boolean, path: PathShape | null) {
    this.live = live;
    this.path = path;
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
  }
}

function radiusOf(v: Length | undefined): number {
  return typeof v === 'number' ? v : 0;
}

// w/h 是容器量到的 vp 尺寸；没量到（0）时不裁，先让材质按矩形出来。
export function bubbleGlassModifier(live: boolean, w: number, h: number, outgoing: boolean,
  hasTail: boolean, radii: BorderRadiuses): BubbleGlassModifier {
  if (!live || w <= 0 || h <= 0) {
    return new BubbleGlassModifier(live, null);
  }
  const commands = glassBubbleCommands(w, h, outgoing, hasTail,
    radiusOf(radii.topLeft), radiusOf(radii.topRight), radiusOf(radii.bottomRight), radiusOf(radii.bottomLeft),
    TAIL_W, TAIL_H, vp2px(1));
  return new BubbleGlassModifier(true, new PathShape({ commands: commands }));
}
