interface ReactionTransitionEntry {
  duration: number;
  effect: TransitionEffect;
}

// Per-shell, per-reaction descriptors. Do not share effects between chips or
// components, and do not retain reactions after their message is released.
// This skips descriptor construction only; duration gating/feedback is intact.
export class ReactionTransitions {
  private entries: WeakMap<Object, ReactionTransitionEntry> = new WeakMap<Object, ReactionTransitionEntry>();

  prepare(reaction: Object, duration: number): TransitionEffect {
    const previous: ReactionTransitionEntry | undefined = this.entries.get(reaction);
    if (previous !== undefined && previous.duration === duration) {
      return previous.effect;
    }
    const effect: TransitionEffect = TransitionEffect.scale({ x: 0.6, y: 0.6 })
      .combine(TransitionEffect.OPACITY)
      .animation({ duration: duration, curve: Curve.EaseOut });
    this.entries.set(reaction, { duration: duration, effect: effect });
    return effect;
  }
}
