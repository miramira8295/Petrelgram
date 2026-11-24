import { KEY_FORCE_SINGLE_COLUMN } from '../store/AppSettings';
import { HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WIDTH_BREAKPOINT, KEY_WINDOW_PORTRAIT,
  WIDTH_BP_SM, isSplitByBreakpoint } from './layoutBreakpoint';

// Transient left-pane selection. The existing breakpoint policy remains the
// only layout switch; navigation destinations stay in the right-hand chat stack.
export const LEFT_PANE_CHATS: string = 'chats';
export const LEFT_PANE_CONTACTS: string = 'contacts';
export const LEFT_PANE_SETTINGS: string = 'settings';
export const LEFT_PANE_PROFILE: string = 'profile';
export const KEY_LEFT_PANE_VIEW: string = 'leftPaneView';

export function splitLeftPaneEnabled(): boolean {
  return isSplitByBreakpoint(AppStorage.get<number>(KEY_WIDTH_BREAKPOINT) ?? WIDTH_BP_SM,
    AppStorage.get<number>(KEY_HEIGHT_BREAKPOINT) ?? HEIGHT_BP_LG,
    AppStorage.get<boolean>(KEY_FORCE_SINGLE_COLUMN) ?? false,
    AppStorage.get<boolean>(KEY_WINDOW_PORTRAIT) ?? true);
}

export function leftPaneView(): string {
  const view: string = AppStorage.get<string>(KEY_LEFT_PANE_VIEW) ?? LEFT_PANE_CHATS;
  return view === LEFT_PANE_CONTACTS || view === LEFT_PANE_SETTINGS || view === LEFT_PANE_PROFILE
    ? view : LEFT_PANE_CHATS;
}

export function showLeftPane(view: string): boolean {
  if (view !== LEFT_PANE_CONTACTS && view !== LEFT_PANE_SETTINGS && view !== LEFT_PANE_PROFILE) {
    return closeLeftPane();
  }
  if (!splitLeftPaneEnabled() || leftPaneView() === view) { return false; }
  AppStorage.setOrCreate<string>(KEY_LEFT_PANE_VIEW, view);
  return true;
}

export function closeLeftPane(): boolean {
  if (leftPaneView() === LEFT_PANE_CHATS) { return false; }
  AppStorage.setOrCreate<string>(KEY_LEFT_PANE_VIEW, LEFT_PANE_CHATS);
  return true;
}
