import { describe, expect, it } from '@ohos/hypium';
import {
  OverlaySurface,
  immersiveMaterialAvailable,
  materialWinsAt,
  overlayBackdropBlur,
  overlayBlur,
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
      }
    });

    it('resolves every surface the same way the device does', 0, () => {
      const available = immersiveMaterialAvailable();
      for (const surface of ALL_SURFACES) {
        expect(overlayMaterial(surface) !== undefined).assertEqual(available);
      }
    });

    it('gives the fallback blur only to the framework menu container', 0, () => {
      if (immersiveMaterialAvailable()) {
        return;
      }
      // BlurStyle.COMPONENT_* carries an opaque backplate. It is right for the
      // framework's own menu container and wrong for every self-drawn surface,
      // where it renders as solid grey (MainScreen.ets:292).
      expect(overlayBlur('menu')).assertEqual(BlurStyle.COMPONENT_ULTRA_THICK);
      expect(overlayBlur('dialog')).assertUndefined();
      expect(overlayBlur('bar')).assertUndefined();
      expect(overlayBlur('card')).assertUndefined();
    });

    it('gives the backdrop blur only to the self-drawn glass bars', 0, () => {
      if (immersiveMaterialAvailable()) {
        return;
      }
      // The radius the dock and the folder bar already used.
      expect(overlayBackdropBlur('bar')).assertEqual(22);
      expect(overlayBackdropBlur('menu')).assertEqual(0);
      expect(overlayBackdropBlur('dialog')).assertEqual(0);
      expect(overlayBackdropBlur('card')).assertEqual(0);
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
