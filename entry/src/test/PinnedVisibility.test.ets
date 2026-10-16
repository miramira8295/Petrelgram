import { describe, expect, it } from '@ohos/hypium';
import { PinnedVisibility, PinnedVisibilityStorage, pinnedVisibilityKey } from '../main/ets/util/pinnedVisibilityState';

class MemoryVisibility implements PinnedVisibilityStorage {
  values: Map<string, boolean> = new Map<string, boolean>();
  read(key: string): boolean { return this.values.get(key) ?? false; }
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
    it('unresolved_identity_does_not_persist', 0, (): void => {
      const storage = new MemoryVisibility();
      expect(pinnedVisibilityKey('', -100)).assertEqual('');
      expect(pinnedVisibilityKey('a', 0)).assertEqual('');
      new PinnedVisibility('', storage).toggle();
      expect(storage.values.size).assertEqual(0);
    });
  });
}
