import { describe, expect, it } from '@ohos/hypium';
import {
  OverlaySurface,
  immersiveMaterialAvailable,
  materialWinsAt,
  overlayBackdropBlur,
  overlayBlur,
  overlayGlassFill,
  overlayMaterial
} from '../main/ets/util/overlayMaterial';

// The immersive system material arrived in API 26. Below it every overlay keeps
// exactly what it shipped with, and the one thing that must never happen is the
// material running on top of a fallback blur — the material's own filter
// already blurs, so stacking is duplicate GPU work with no visual gain.
//
// The API-version tests are pure. The rest run against whatever device the
// suite is on, so they assert the invariant rather than one side of it.

const ALL_SURFACES: OverlaySurface[] = ['menu', 'dialog', 'bar', 'card'];

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
        expect(overlayGlassFill(surface, $r('app.color.surface'))).assertDeepEquals($r('app.color.surface'));
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
        if (immersiveMaterialAvailable()) {
          // 材质自带填充，底色原样交回，由材质清成透明玻璃。
          expect(fill === solid).assertTrue();
        } else {
          expect(fill === solid).assertFalse();
        }
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
  });
}
