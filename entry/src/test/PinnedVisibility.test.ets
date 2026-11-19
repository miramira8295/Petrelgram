import { describe, expect, it, beforeEach, afterEach } from '@ohos/hypium';
import { PinnedVisibility, pinnedVisibilityDefaults, KEY_HIDE_PINNED_DEFAULT } from '../main/ets/util/pinnedVisibilityState';
import { pinnedVisibilityFor } from '../main/ets/services/PinnedVisibility';
import { setBoolean } from '../main/ets/store/AppSettings';

export default function pinnedVisibilityTest() {
  describe('PinnedVisibility', (): void => {
    let saved: boolean = false;
    beforeEach((): void => {
      saved = pinnedVisibilityDefaults.hidden;
      setBoolean(KEY_HIDE_PINNED_DEFAULT, false);
    });
    afterEach((): void => { setBoolean(KEY_HIDE_PINNED_DEFAULT, saved); });
    it('settings_hide_updates_existing_reader', 0, (): void => {
      const state = new PinnedVisibility();
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      expect(state.hidden).assertTrue();
    });
    it('settings_show_updates_existing_reader', 0, (): void => {
      const state = new PinnedVisibility();
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      setBoolean(KEY_HIDE_PINNED_DEFAULT, false);
      expect(state.hidden).assertFalse();
    });
    it('reopened_chat_reads_current_global_choice', 0, (): void => {
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      expect(new PinnedVisibility().hidden).assertTrue();
    });
    it('different_chats_share_one_reader', 0, (): void => {
      expect(pinnedVisibilityFor(-100) === pinnedVisibilityFor(-200)).assertTrue();
    });
    it('global_change_reaches_all_open_chats', 0, (): void => {
      const first = pinnedVisibilityFor(-100);
      const second = pinnedVisibilityFor(-200);
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      expect(first.hidden).assertTrue(); expect(second.hidden).assertTrue();
    });
    it('unresolved_chat_uses_global_choice_without_account_lookup', 0, (): void => {
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      expect(pinnedVisibilityFor(0).hidden).assertTrue();
    });
    it('settings_storage_and_reader_remain_in_sync', 0, (): void => {
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      expect(AppStorage.get<boolean>(KEY_HIDE_PINNED_DEFAULT)).assertTrue();
      expect(pinnedVisibilityFor(7).hidden).assertTrue();
    });
    it('repeated_writes_do_not_create_chat_overrides', 0, (): void => {
      const state = pinnedVisibilityFor(9);
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      setBoolean(KEY_HIDE_PINNED_DEFAULT, true);
      setBoolean(KEY_HIDE_PINNED_DEFAULT, false);
      expect(state.hidden).assertFalse();
      expect(pinnedVisibilityFor(10).hidden).assertFalse();
    });
  });
}
