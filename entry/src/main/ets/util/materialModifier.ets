import { OverlaySurface, overlayMaterial } from './overlayMaterial';

// systemMaterial 属性的**唯一**出口。
//
// .systemMaterial(...) 是 API 26 才有的组件属性。直接链式调用的话，方法本身
// 在低版本运行时里就不存在，页面一构建就抛——这不是"参数传 undefined 会被
// 忽略"能救的：炸在取方法那一步，参数还没轮到求值。全应用底线是 6.0.0(20)，
// 所以任何页面都不允许直接写 .systemMaterial(...)。
//
// 出口收在 AttributeModifier 里：apply 时先问 overlayMaterial —— 它内部有
// 26 的版本闸门，低版本返回 undefined —— 拿不到材质就**根本不碰**那个方法。
// 于是"调不调"由运行时版本决定，构造上就安全，不依赖任何"低版本会忽略"
// 的猜测。低版本上观感由各调用点自己的 backdropBlur/overlayGlassFill 降级
// 路径接住，和以前一致。
//
// 修饰器按面缓存：apply 每次都现取材质，材质缓存（含用户厚度/光感档位）在
// overlayMaterial 里自己失效，这里不用管。
export class SurfaceMaterialModifier implements AttributeModifier<CommonAttribute> {
  private readonly surface: OverlaySurface;

  constructor(surface: OverlaySurface) {
    this.surface = surface;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const material = overlayMaterial(this.surface);
    if (material !== undefined) {
      instance.systemMaterial(material);
    }
  }
}

const cache: Map<string, SurfaceMaterialModifier> = new Map<string, SurfaceMaterialModifier>();

export function materialModifier(surface: OverlaySurface): SurfaceMaterialModifier {
  const hit = cache.get(surface);
  if (hit !== undefined) {
    return hit;
  }
  const built = new SurfaceMaterialModifier(surface);
  cache.set(surface, built);
  return built;
}
