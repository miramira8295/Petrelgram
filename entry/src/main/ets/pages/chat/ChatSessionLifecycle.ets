/**
 * Owns the ordering of ChatPage's final teardown.
 *
 * The page still owns every stateful subsystem and supplies the concrete
 * actions. Keeping the ordering here makes page exit a single contract while
 * leaving timeline/list behavior untouched.
 */
export interface ChatSessionLifecycleHooks {
  invalidateScrollWork: () => void;
  cancelDropReceiver: () => void;
  publishViewerCovered: () => void;
  disposeShareTargeted: () => void;
  disposeInitialStageAndTgs: () => void;
  disposePlaybackAndSlots: () => void;
  persistDraftAndViewport: () => void;
  disposeTimersAndSeqGuards: () => void;
  stopVoicePlaybackKeepingMusic: () => void;
  disposeSubscriptionsInOrder: () => void;
  closeStores: () => void;
}

export class ChatSessionLifecycle {
  private hooks: ChatSessionLifecycleHooks | null = null;

  bind(hooks: ChatSessionLifecycleHooks): void {
    this.hooks = hooks;
  }

  dispose(): void {
    const hooks: ChatSessionLifecycleHooks | null = this.hooks;
    if (hooks === null) {
      return;
    }
    hooks.invalidateScrollWork();
    hooks.cancelDropReceiver();
    hooks.publishViewerCovered();
    hooks.disposeShareTargeted();
    hooks.disposeInitialStageAndTgs();
    hooks.disposePlaybackAndSlots();
    hooks.persistDraftAndViewport();
    hooks.disposeTimersAndSeqGuards();
    hooks.stopVoicePlaybackKeepingMusic();
    hooks.disposeSubscriptionsInOrder();
    hooks.closeStores();
  }
}
