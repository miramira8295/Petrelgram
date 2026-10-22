import { describe, expect, it } from '@ohos/hypium';
import { PinnedVisibility, PinnedVisibilityDefaults, PinnedVisibilityStorage, pinnedVisibilityKey } from '../main/ets/util/pinnedVisibilityState';

class MemoryVisibility implements PinnedVisibilityStorage {
  values: Map<string, boolean> = new Map<string, boolean>();
  read(key: string): boolean | undefined { return this.values.get(key); }
  write(key: string, hidden: boolean): void { this.values.set(key, hidden); }
}
export default function pinnedVisibilityTest() {
  describe('PinnedVisibility', (): void => {
    it('hide_and_show_survive_new_session', 0, (): void => {
      const storage = new MemoryVisibility();
      const key = pinnedVisibilityKey('a', -100);
      const state = new PinnedVisibility(key, storage);
      expect(state.hidden).assertFalse(); state.toggle();
      const reopened = new PinnedVisibility(key, storage);
      expect(reopened.hidden).assertTrue(); reopened.toggle();
      expect(new PinnedVisibility(key, storage).hidden).assertFalse();
    });
    it('accounts_and_chats_are_isolated', 0, (): void => {
      const storage = new MemoryVisibility();
      new PinnedVisibility(pinnedVisibilityKey('a', -100), storage).toggle();
      expect(new PinnedVisibility(pinnedVisibilityKey('b', -100), storage).hidden).assertFalse();
      expect(new PinnedVisibility(pinnedVisibilityKey('a', -200), storage).hidden).assertFalse();
    });
    it('unconfigured_chats_follow_global_changes', 0, (): void => {
      const defaults = new PinnedVisibilityDefaults();
      const state = new PinnedVisibility('a:1', new MemoryVisibility(), defaults);
      expect(state.hidden).assertFalse();
      defaults.hidden = true;
      expect(state.hidden).assertTrue();
      defaults.hidden = false;
      expect(state.hidden).assertFalse();
    });
    it('explicit_show_survives_global_hide_and_reopen', 0, (): void => {
      const defaults = new PinnedVisibilityDefaults(); defaults.hidden = true;
      const storage = new MemoryVisibility();
      const state = new PinnedVisibility('a:1', storage, defaults);
      state.toggle();
      expect(state.hidden).assertFalse();
      defaults.hidden = false; defaults.hidden = true;
      expect(new PinnedVisibility('a:1', storage, defaults).hidden).assertFalse();
    });
    it('explicit_hide_survives_global_show', 0, (): void => {
      const defaults = new PinnedVisibilityDefaults();
      const storage = new MemoryVisibility();
      const state = new PinnedVisibility('a:1', storage, defaults);
      state.toggle(); defaults.hidden = true; defaults.hidden = false;
      expect(new PinnedVisibility('a:1', storage, defaults).hidden).assertTrue();
    });
    it('legacy_boolean_choices_take_priority', 0, (): void => {
      const defaults = new PinnedVisibilityDefaults(); defaults.hidden = true;
      const storage = new MemoryVisibility();
      storage.values.set('a:1', false); storage.values.set('a:2', true);
      expect(new PinnedVisibility('a:1', storage, defaults).hidden).assertFalse();
      defaults.hidden = false;
      expect(new PinnedVisibility('a:2', storage, defaults).hidden).assertTrue();
      expect(new PinnedVisibility('b:1', storage, defaults).hidden).assertFalse();
    });
    it('failed_write_does_not_replace_inherited_value', 0, (): void => {
      const defaults = new PinnedVisibilityDefaults(); defaults.hidden = true;
      const storage: PinnedVisibilityStorage = {
        read: (_key: string): boolean | undefined => undefined,
        write: (_key: string, _hidden: boolean): void => { throw new Error('write failed'); }
      };
      const state = new PinnedVisibility('a:1', storage, defaults);
      try { state.toggle(); } catch (_) {}
      expect(state.hidden).assertTrue();
      defaults.hidden = false;
      expect(state.hidden).assertFalse();
    });
    it('unresolved_identity_does_not_persist', 0, (): void => {
      const storage = new MemoryVisibility();
      expect(pinnedVisibilityKey('', -100)).assertEqual('');
      expect(pinnedVisibilityKey('a', 0)).assertEqual('');
      new PinnedVisibility('', storage).toggle();
      expect(storage.values.size).assertEqual(0);
    });
  });
}
