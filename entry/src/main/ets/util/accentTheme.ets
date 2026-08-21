import { common } from '@kit.AbilityKit';
import { getAccentColorStore } from '../tdkit/Globals';
import { AccentPalettes } from '../store/AccentColorStore';
import { TdError, TdObject } from '../tdkit/TdTypes';
import { profileAccentPreviewOf } from './accentPresentation';
import { applyAccentPrimary, darkResourceMode } from './theme';
import { logE } from './log';

// Re-derives the app primary color from the account's profile accent color.
// No selection (or no palette entry) restores the built-in primary.
export function syncAccentPrimary(context: common.UIAbilityContext): void {
  const palettes: AccentPalettes = getAccentColorStore().palettes();
  getAccentColorStore().currentSelection().then((ids: [number, number]): void => {
    const profileId = ids[1];
    const raw = palettes.profileColors.find((entry: TdObject): boolean =>
      ((entry['id'] as number | undefined) ?? -1) === profileId
    );
    if (raw === undefined) {
      applyAccentPrimary('');
      return;
    }
    const preview = profileAccentPreviewOf(raw, darkResourceMode(context));
    applyAccentPrimary(preview !== null && preview.colors.length > 0 ? preview.colors[0] : '');
  }).catch((error: TdError): void => {
    logE(`accentTheme.sync failed: ${error.message}`);
  });
}

// Follows palette pushes for the app's lifetime on the main screen; returns
// the unsubscribe handle.
export function bindAccentPrimary(context: common.UIAbilityContext): () => void {
  return getAccentColorStore().subscribe((_palettes: AccentPalettes): void => {
    syncAccentPrimary(context);
  });
}
