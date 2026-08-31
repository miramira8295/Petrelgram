// Small, page-agnostic coordination helpers for ChatPage's NavDestination
// lifecycle. The page remains the owner of all state and side effects.

export interface ChatPageHiddenHooks {
  suspendScrollVisual: () => void;
  endLinkNavigation: () => void;
  cancelInitialTransition: () => void;
  setPageVisible: (visible: boolean) => void;
  syncChatTgsGate: () => void;
  captureHiddenAnchor: () => void;
  clearNowSecTimer: () => void;
  clearSlotTick: () => void;
  suspendPlaySlots: () => void;
}

export function coordinateChatPageHidden(hooks: ChatPageHiddenHooks): void {
  hooks.suspendScrollVisual();
  hooks.endLinkNavigation();
  hooks.cancelInitialTransition();
  hooks.setPageVisible(false);
  hooks.syncChatTgsGate();
  hooks.captureHiddenAnchor();
  hooks.clearNowSecTimer();
  hooks.clearSlotTick();
  hooks.suspendPlaySlots();
}

export interface ChatPageWillHideHooks {
  suspendScrollVisual: () => void;
  cancelInitialTransition: () => void;
  setPageVisible: (visible: boolean) => void;
  syncChatTgsGate: () => void;
  clearNowSecTimer: () => void;
  clearSlotTick: () => void;
  suspendPlaySlots: () => void;
}

export function coordinateChatPageWillHide(hooks: ChatPageWillHideHooks): void {
  hooks.suspendScrollVisual();
  hooks.cancelInitialTransition();
  hooks.setPageVisible(false);
  hooks.syncChatTgsGate();
  hooks.clearNowSecTimer();
  hooks.clearSlotTick();
  hooks.suspendPlaySlots();
}

export interface ChatPageShownState {
  hiddenSinceMs: number;
  appWentBackground: boolean;
  hiddenListDirty: boolean;
}

export interface ChatPageShownHooks {
  resumeScrollVisual: () => void;
  setPageVisible: (visible: boolean) => void;
  armInitialTransitionSettle: () => void;
  scheduleInitialTimelinePresentation: () => void;
  scheduleChatTgsResume: () => void;
  endLinkNavigation: () => void;
  armPlaySlotSettle: () => void;
  resyncListAfterHidden: () => void;
  setNowSec: (value: number) => void;
  armNowSecTimer: () => void;
  clearLiveNavigationBusy: () => void;
  chatId: () => number;
  refreshVideoChat: () => void;
}

export function coordinateChatPageShown(
  state: ChatPageShownState, hooks: ChatPageShownHooks
): void {
  hooks.resumeScrollVisual();
  hooks.setPageVisible(true);
  hooks.armInitialTransitionSettle();
  hooks.scheduleInitialTimelinePresentation();
  hooks.scheduleChatTgsResume();
  hooks.endLinkNavigation();
  hooks.armPlaySlotSettle();

  state.hiddenSinceMs = 0;
  const wasBackgrounded: boolean = state.appWentBackground;
  state.appWentBackground = false;
  if (state.hiddenListDirty || wasBackgrounded) {
    state.hiddenListDirty = false;
    hooks.resyncListAfterHidden();
  }
  hooks.setNowSec(Math.floor(Date.now() / 1000));
  hooks.armNowSecTimer();
  hooks.clearLiveNavigationBusy();
  if (hooks.chatId() > 0) {
    hooks.refreshVideoChat();
  }
}
