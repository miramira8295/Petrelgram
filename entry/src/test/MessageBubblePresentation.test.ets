import { describe, expect, it } from '@ohos/hypium';
import { BubbleCornerCache, SenderAvatarSpecCache } from '../main/ets/util/messageBubblePresentation';

export default function messageBubblePresentationTest() {
  describe('MessageBubblePresentation', () => {
    it('equivalent_avatar_inputs_keep_the_same_spec', 0, () => {
      const cache = new SenderAvatarSpecCache();
      const first = cache.prepare(10, true, '/a', 'A', 38, true);
      expect(cache.prepare(10, true, '/a', 'A', 38, true) === first).assertTrue();
    });
    it('avatar_identity_includes_user_or_chat_kind', 0, () => {
      const cache = new SenderAvatarSpecCache();
      const first = cache.prepare(10, true, '/a', 'A', 38, true);
      const next = cache.prepare(10, false, '/c', 'C', 38, true);
      expect(next === first).assertFalse();
      expect(next.senderIsUser).assertFalse();
      expect(first.initialPath).assertEqual('/a');
      expect(cache.prepare(11, false, '/c', 'C', 38, true) === next).assertFalse();
    });
    it('avatar_path_initials_size_and_animation_invalidate_independently', 0, () => {
      const cache = new SenderAvatarSpecCache();
      const first = cache.prepare(10, true, '/a', 'A', 38, true);
      const path = cache.prepare(10, true, '/b', 'A', 38, true);
      const initials = cache.prepare(10, true, '/b', 'B', 38, true);
      const size = cache.prepare(10, true, '/b', 'B', 22, true);
      const animation = cache.prepare(10, true, '/b', 'B', 22, false);
      expect(first === path || path === initials || initials === size || size === animation).assertFalse();
      expect(first.avatarSize).assertEqual(38);
      expect(animation.avatarSize).assertEqual(22);
      expect(animation.animate).assertFalse();
    });
    it('avatar_slots_do_not_share_previous_sender_state', 0, () => {
      const one = new SenderAvatarSpecCache();
      const two = new SenderAvatarSpecCache();
      const previous = one.prepare(10, true, '/a', '?', 22, false);
      two.prepare(11, true, '/b', '?', 22, false);
      expect(one.prepare(10, true, '/a', '?', 22, false) === previous).assertTrue();
    });
    it('tail_bubbles_use_the_same_radius_for_both_bottom_corners', 0, () => {
      const cache = new BubbleCornerCache();
      const incoming = cache.prepare(18, false, true, true);
      const outgoing = cache.prepare(18, true, true, true);
      expect(incoming.topLeft).assertEqual(18);
      expect(incoming.bottomLeft).assertEqual(18);
      expect(incoming.bottomRight).assertEqual(18);
      expect(outgoing.bottomLeft).assertEqual(18);
      expect(outgoing.bottomRight).assertEqual(18);
    });
    it('middle_run_corners_keep_the_seven_vp_limit', 0, () => {
      const cache = new BubbleCornerCache();
      const corners = cache.prepare(18, false, false, false);
      expect(corners.topLeft).assertEqual(7);
      expect(corners.bottomLeft).assertEqual(7);
      expect(corners.topRight).assertEqual(18);
      expect(corners.bottomRight).assertEqual(18);
    });
    it('radius_setting_changes_refresh_without_mutating_previous_corners', 0, () => {
      const cache = new BubbleCornerCache();
      const first = cache.prepare(18, false, true, true);
      expect(cache.prepare(18, false, true, true) === first).assertTrue();
      const small = cache.prepare(1, false, true, true);
      expect(small === first).assertFalse();
      expect(small.topLeft).assertEqual(1);
      expect(small.bottomLeft).assertEqual(1);
      expect(first.bottomLeft).assertEqual(18);
      const square = cache.prepare(0, true, false, false);
      expect(square.topLeft).assertEqual(0);
      expect(square.bottomRight).assertEqual(0);
    });
    it('sender_grouping_and_avatar_grouping_refresh_corners', 0, () => {
      const cache = new BubbleCornerCache();
      const middle = cache.prepare(18, false, false, false);
      const start = cache.prepare(18, false, true, false);
      const end = cache.prepare(18, false, true, true);
      expect(middle === start || start === end).assertFalse();
      expect(middle.topLeft).assertEqual(7);
      expect(start.topLeft).assertEqual(18);
      expect(start.bottomLeft).assertEqual(7);
      expect(end.bottomLeft).assertEqual(18);
    });
  });
}
