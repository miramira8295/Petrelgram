// Android ReactionsLayoutInBubble normal chips: 26dp high, 20dp icon,
// 8dp edge padding and 4dp spacing (6dp before a custom emoji counter).
export const REACTION_ICON_VP: number = 20;
export const REACTION_HEIGHT_VP: number = 26;
export const REACTION_PADDING_VP: number = 8;
export function reactionCountGap(custom: boolean): number { return custom ? 6 : 4; }

export function reactionFill(outgoing: boolean, chosen: boolean): ResourceColor {
  return outgoing ? (chosen ? $r('app.color.reaction_out_selected') : $r('app.color.reaction_out')) :
    (chosen ? $r('app.color.reaction_in_selected') : $r('app.color.reaction_in'));
}
export function reactionForeground(outgoing: boolean, chosen: boolean): ResourceColor {
  return chosen ? Color.White : (outgoing ? $r('app.color.reaction_out_text') : $r('app.color.reaction_in_text'));
}
