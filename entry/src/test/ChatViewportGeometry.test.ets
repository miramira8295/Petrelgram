import { describe, expect, it } from '@ohos/hypium';
import {
  ViewportGeometrySplice, planViewportGeometrySplice, rememberViewportRowHeight,
  rememberedViewportRowHeight, resetChatViewportGeometry, viewportGeometryKey
} from '../main/ets/util/chatViewportGeometry';

export default function chatViewportGeometryTest() {
  describe('chatViewportGeometry', () => {
    it('separates geometry by conversation width language content and divider', 0, (): void => {
      const base: string = viewportGeometryKey(1, 0, 5, 'row-a', 360, 0, false);
      expect(viewportGeometryKey(2, 0, 5, 'row-a', 360, 0, false) === base).assertFalse();
      expect(viewportGeometryKey(1, 7, 5, 'row-a', 360, 0, false) === base).assertFalse();
      expect(viewportGeometryKey(1, 0, 5, 'row-a', 720, 0, false) === base).assertFalse();
      expect(viewportGeometryKey(1, 0, 5, 'row-a', 360, 1, false) === base).assertFalse();
      expect(viewportGeometryKey(1, 0, 5, 'row-b', 360, 0, false) === base).assertFalse();
      expect(viewportGeometryKey(1, 0, 5, 'row-a', 360, 0, true) === base).assertFalse();
    });

    it('keeps a measured row height for the next page instance', 0, (): void => {
      resetChatViewportGeometry();
      const key: string = viewportGeometryKey(1, 0, 9, 'message', 360, 0, false);
      rememberViewportRowHeight(key, 137.5);
      expect(rememberedViewportRowHeight(key)).assertEqual(137.5);
      rememberViewportRowHeight(key, Number.NaN);
      expect(rememberedViewportRowHeight(key)).assertEqual(137.5);
    });

    it('uses a narrow splice for prepends', 0, (): void => {
      const plan: ViewportGeometrySplice = planViewportGeometrySplice(
        ['c', 'd'], ['a', 'b', 'c', 'd'], [10, 20, 30, 40]);
      expect(plan.start).assertEqual(0);
      expect(plan.deleteCount).assertEqual(0);
      expect(plan.sizes.length).assertEqual(2);
      expect(plan.sizes[0]).assertEqual(10);
      expect(plan.sizes[1]).assertEqual(20);
    });

    it('replaces only the changed middle geometry', 0, (): void => {
      const plan: ViewportGeometrySplice = planViewportGeometrySplice(
        ['a', 'old', 'd'], ['a', 'new-1', 'new-2', 'd'], [10, 20, 30, 40]);
      expect(plan.start).assertEqual(1);
      expect(plan.deleteCount).assertEqual(1);
      expect(plan.sizes.length).assertEqual(2);
      expect(plan.sizes[0]).assertEqual(20);
      expect(plan.sizes[1]).assertEqual(30);
    });
  });
}
