import { preferences } from '@kit.ArkData';
import { getActiveTdAccountSlot, getUiAbilityContext } from '../tdkit/Globals';
import { PinnedVisibility, PinnedVisibilityStorage, pinnedVisibilityKey } from '../util/pinnedVisibilityState';
import { logE } from '../util/log';

// All open views of one account/chat share the same observable preference.
const states: Map<string, PinnedVisibility> = new Map<string, PinnedVisibility>();
export function pinnedVisibilityFor(chatId: number): PinnedVisibility {
  const key = pinnedVisibilityKey(getActiveTdAccountSlot(), chatId);
  if (key === '') { return new PinnedVisibility(); }
  const existing = states.get(key);
  if (existing !== undefined) { return existing; }
  const context = getUiAbilityContext();
  if (context === null) { return new PinnedVisibility(); }
  try {
    const store = preferences.getPreferencesSync(context, { name: 'pinned_visibility' });
    const storage: PinnedVisibilityStorage = {
      read: (name: string): boolean => store.getSync(name, false) === true,
      write: (name: string, hidden: boolean): void => {
        store.putSync(name, hidden);
        store.flush().catch((): void => { logE('PinnedVisibility flush failed'); });
      }
    };
    const state = new PinnedVisibility(key, storage);
    states.set(key, state);
    return state;
  } catch (_) {
    logE('PinnedVisibility read failed');
    return new PinnedVisibility();
  }
}
