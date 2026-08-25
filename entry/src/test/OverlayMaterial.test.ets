import { describe, expect, it } from '@ohos/hypium';
import {
  OverlaySurface,
  immersiveMaterialAvailable,
  materialWinsAt,
  overlayBackdropBlur,
  overlayBlur,
  overlayGlassFill,
  overlayMaterial,
  pressAnimationWins,
  usesImmersiveMaterial
} from '../main/ets/util/overlayMaterial';

// The immersive system material arrived in API 26. Below it every overlay keeps
// exactly what it shipped with, and the one thing that must never happen is the
// material running on top of a fallback blur — the material's own filter
// already blurs, so stacking is duplicate GPU work with no visual gain.
//
// The API-version tests are pure. The rest run against whatever device the
// suite is on, so they assert the invariant rather than one side of it.

const ALL_SURFACES: OverlaySurface[] = ['menu', 'dialog', 'bar', 'card', 'control', 'viewer'];

export default function overlayMaterialTest() {
  describe('overlayMaterial', () => {
    it('turns the material on exactly at API 26', 0, () => {
      expect(materialWinsAt(26)).assertTrue();
      expect(materialWinsAt(25)).assertFalse();
    });

    it('leaves every API level the app ships against on the fallback', 0, () => {
      // compatibleSdkVersion is 6.0.0(20); the target was 6.1.1(24) before this.
      expect(materialWinsAt(20)).assertFalse();
      expect(materialWinsAt(24)).assertFalse();
    });

    it('keeps the material on past 26', 0, () => {
      expect(materialWinsAt(27)).assertTrue();
      expect(materialWinsAt(99)).assertTrue();
    });

    it('never runs a material and a fallback blur on the same surface', 0, () => {
      for (const surface of ALL_SURFACES) {
        if (overlayMaterial(surface) === undefined) {
          continue;
        }
        expect(overlayBlur(surface)).assertUndefined();
        expect(overlayBackdropBlur(surface)).assertEqual(0);
        // 底色也不能再被换成半透明：材质会自己把填充清成玻璃。
        // 材质在时底色必须透明，否则材质被盖住。
        expect(overlayGlassFill(surface, $r('app.color.surface')) === Color.Transparent).assertTrue();
      }
    });

    it('resolves every surface the same way the device does', 0, () => {
      const available = immersiveMaterialAvailable();
      for (const surface of ALL_SURFACES) {
        expect(overlayMaterial(surface) !== undefined).assertEqual(available);
      }
    });

    // BlurStyle.COMPONENT_* carries an opaque backplate: right for a framework
    // container, and wrong for every self-drawn surface, where it renders as
    // solid grey (MainScreen.ets:292). That is why only the framework surfaces
    // may ever be handed one — this is the invariant, not the list of surfaces.
    it('offers BlurStyle only to the framework containers', 0, () => {
      if (immersiveMaterialAvailable()) {
        return;
      }
      expect(overlayBlur('menu')).assertEqual(BlurStyle.COMPONENT_ULTRA_THICK);
      expect(overlayBlur('dialog')).assertEqual(BlurStyle.COMPONENT_ULTRA_THICK);
      // 自绘面永远不给 BlurStyle，给了就是一块死灰。
      expect(overlayBlur('bar')).assertUndefined();
      expect(overlayBlur('card')).assertUndefined();
    });

    // 毛玻璃本身要的 API 远低于沉浸光感：backdropBlur 从 7 起，
    // backgroundBlurStyle 从 9 起。所以低版本上每个自绘面都画得出玻璃，
    // 由调用点决定用不用——这个 getter 只管"材质没接管时给多少半径"。
    it('offers a backdrop-blur radius on every surface below the material', 0, () => {
      if (immersiveMaterialAvailable()) {
        return;
      }
      // The radius the dock and the folder bar already used.
      for (const surface of ALL_SURFACES) {
        expect(overlayBackdropBlur(surface)).assertEqual(22);
      }
    });

    // 不透明底色会把 backdropBlur 完全盖住——模糊的是身后的东西，而它自己
    // 不透光。所以自绘玻璃的两半必须一起出现：换半透明底 + 加模糊。
    it('swaps the solid fill for a translucent one wherever it self-draws glass', 0, () => {
      const solid: ResourceColor = $r('app.color.surface');
      for (const surface of ALL_SURFACES) {
        const fill = overlayGlassFill(surface, solid);
        // 两种情况都不能是原来那个不透明实色，理由不同：材质在时它会盖住
        // 材质层（官方 FAQ 明写材质层级在 backgroundColor 之下）；材质不在
        // 时它会盖住 backdropBlur。
        expect(fill === solid).assertFalse();
      }
    });

    it('reuses one material object per surface', 0, () => {
      if (!immersiveMaterialAvailable()) {
        return;
      }
      // Rebuilding a material per frame re-triggers the material computation;
      // these parameters never change, so the object must not either.
      for (const surface of ALL_SURFACES) {
        expect(overlayMaterial(surface) === overlayMaterial(surface)).assertTrue();
      }
    });

    it('does not share one material across surfaces', 0, () => {
      if (!immersiveMaterialAvailable()) {
        return;
      }
      expect(overlayMaterial('menu') === overlayMaterial('dialog')).assertFalse();
      expect(overlayMaterial('bar') === overlayMaterial('card')).assertFalse();
    });

    // 手写按压动画和材质的 interactive 不能同时存在——两层形变叠加是官方
    // 明确点名的坑。这条钉的是"恰好一个负责按压"，不是某一边的具体写法。
    it('never runs a hand-written press animation alongside the material one', 0, () => {
      // 只有 'control' 开 interactive，所以只有它会把手写动画让出去。
      expect(pressAnimationWins('control')).assertEqual(!immersiveMaterialAvailable());
    });

    // 其余几档是背景板，不该在触摸时变形，手写动画永远说了算。
    it('leaves the press animation to the caller on every non-control surface', 0, () => {
      for (const surface of ALL_SURFACES) {
        if (surface === 'control') {
          continue;
        }
        expect(pressAnimationWins(surface)).assertTrue();
      }
    });

    // 形变和光晕是两件事，故意不同范围：形变只给可按压的控件（'control'），
    // 光晕还给面板和浮条——摸上去发光不改变任何几何，叠在大面积背景上没有
    // 副作用，而整块面板跟着手指变形会很怪。
    //
    // 这条钉的是"形变的范围不能宽于光晕"：反过来就意味着某个面会变形却不发光。
    it('never deforms a surface it does not also light up', 0, () => {
      for (const surface of ALL_SURFACES) {
        if (!pressAnimationWins(surface)) {
          // 材质接管了按压 = 这个面开了 interactive，那它必须也在光晕范围内。
          expect(immersiveMaterialAvailable()).assertTrue();
        }
      }
    });

    // ——— 'viewer' 退出沉浸材质 ———
    //
    // 沉浸材质的前提是"适应身后的东西"，而这一面身后是**用户随便一张照片**：
    // 材质算出来是亮是暗全看那张图，前景色再怎么跟也总有一半照片不成立。
    // #122 把顶栏做成通栏之后仍然看不清，就是因为通栏底色是透明的、观感全
    // 交给了材质。三条不变量必须一起成立，缺一条这一面就又"看不清"了。

    it('viewer 的底色恒为固定深色半透明，与 API 无关', 0, () => {
      const solid: ResourceColor = $r('app.color.surface');
      const viewerFill: ResourceColor = overlayGlassFill('viewer', solid);
      expect(viewerFill as string).assertEqual('#6e3e3e40');
      // 别的面在有材质时是透明（把观感让给材质），无材质时回退 dock_glass
      // ——两种情况都不等于 viewer 这个固定值。
      expect(`${viewerFill}` === `${overlayGlassFill('bar', solid)}`).assertFalse();
    });

    // **判据本身**要被钉住，不能只测 overlayMaterial()：宿主单测里
    // materialAvailable 恒为假，那个函数在改动前后都返回 undefined，测它等于
    // 没测。真正的行为差别只在 API 26 的设备上，而设备上跑不了这些用例。
    it('只有 viewer 退出沉浸材质，别的面照旧', 0, () => {
      expect(usesImmersiveMaterial('viewer')).assertFalse();
      for (const surface of ALL_SURFACES) {
        if (surface !== 'viewer') {
          expect(usesImmersiveMaterial(surface)).assertTrue();
        }
      }
    });

    it('viewer 拿不到材质', 0, () => {
      // 拿得到就会被 SurfaceMaterialModifier 挂上 systemMaterial，底色随即
      // 被材质层盖住——回到"看不清"。
      expect(overlayMaterial('viewer')).assertUndefined();
    });

    it('viewer 的模糊半径恒大于 0', 0, () => {
      // 返回 0 的语义是"把观感让给材质"，而它没有材质可让：0 意味着这一面
      // 只剩一层半透明色，身后的照片纹理会直接透上来压住文字。
      expect(overlayBackdropBlur('viewer') > 0).assertTrue();
    });
  });
}
