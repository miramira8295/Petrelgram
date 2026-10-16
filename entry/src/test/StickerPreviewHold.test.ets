import { describe, expect, it } from '@ohos/hypium';
import { StickerPreviewHold } from '../main/ets/pages/chat/StickerPreviewHold';

export default function stickerPreviewHoldTest() {
  describe('StickerPreviewHold', (): void => {
    it('release_without_drag_does_not_send', 0, (): void => {
      const h = new StickerPreviewHold(); let sent = true;
      h.onFinish = (send: boolean): void => { sent = send; };
      h.bounds(100, 100, 240, 240); h.begin(); h.finish(120, 120, false);
      expect(sent).assertFalse();
    });
    it('drag_inside_sends_once', 0, (): void => {
      const h = new StickerPreviewHold(); let count = 0; let sent = false;
      h.onFinish = (send: boolean): void => { count++; sent = send; };
      h.bounds(100, 100, 240, 240); h.begin(); h.move(120, 120);
      h.finish(120, 120, false); h.finish(120, 120, false);
      expect(sent).assertTrue(); expect(count).assertEqual(1);
    });
    it('drag_out_clears_selection', 0, (): void => {
      const h = new StickerPreviewHold(); let selected = false; let sent = true;
      h.onSelection = (value: boolean): void => { selected = value; };
      h.onFinish = (send: boolean): void => { sent = send; };
      h.bounds(100, 100, 240, 240); h.begin(); h.move(120, 120);
      expect(selected).assertTrue(); h.move(20, 20); expect(selected).assertFalse();
      h.finish(20, 20, false); expect(sent).assertFalse();
    });
    it('cancelled_touch_never_sends', 0, (): void => {
      const h = new StickerPreviewHold(); let sent = true;
      h.onFinish = (send: boolean): void => { sent = send; };
      h.bounds(100, 100, 240, 240); h.begin(); h.move(120, 120); h.finish(120, 120, true);
      expect(sent).assertFalse();
    });
    it('owner_cancel_discards_late_release', 0, (): void => {
      const h = new StickerPreviewHold(); let count = 0;
      h.onFinish = (): void => { count++; };
      h.bounds(100, 100, 240, 240); h.begin(); h.move(120, 120); h.cancel(); h.finish(120, 120, false);
      expect(count).assertEqual(0);
    });
    it('release_rechecks_final_position', 0, (): void => {
      const h = new StickerPreviewHold(); let sent = true;
      h.onFinish = (send: boolean): void => { sent = send; };
      h.bounds(100, 100, 240, 240); h.begin(); h.move(120, 120); h.finish(99, 120, false);
      expect(sent).assertFalse();
    });
  });
}
