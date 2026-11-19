import { MessageEntry } from '../../store/MessageEntry';
import { DrawnBubblePlan } from './DrawnBubblePlan';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { formatClockTime } from '../../util/formatTime';
import { str, plural } from '../../util/strings';

interface DrawnSemanticTarget extends DrawnAlbumRect {
  key: string;
  label: string;
  menu: boolean;
  selected?: boolean;
}

// Equivalent to Android's virtual descendants: accessibility targets accompany
// the same paint plan. They exist only while screen reading is enabled.
@ComponentV2
export struct DrawnRowAccessibility {
  @Require @Param plan: DrawnBubblePlan | null;
  @Require @Param msg: MessageEntry;
  @Param sendState: string = '';
  @Event onActivate: (x: number, y: number, event: ClickEvent) => void =
    (_x: number, _y: number, _event: ClickEvent): void => {};
  @Event onMenu: () => void = (): void => {};

  @Computed
  private get targets(): DrawnSemanticTarget[] {
    const p = this.plan;
    if (p === null) { return []; }
    const targets: DrawnSemanticTarget[] = [];
    targets.push({ key: 'body', label: this.msg.senderName + '\n' +
      (p.caption?.accessibilityText ?? '') + '\n' + formatClockTime(this.msg.date) + (this.msg.isOutgoing ? ' ' +
        str(this.sendState === 'sending' ? 'a11y_message_sending' : this.sendState === 'failed' ? 'a11y_message_failed' :
          this.sendState === 'read' ? 'a11y_message_read' : 'a11y_message_sent') : ''), menu: true,
      x: p.bubbleX, y: p.bubbleY, width: Math.max(1, p.width - p.bubbleX), height: p.height });
    if (p.avatar.width > 0 && this.msg.senderIsUser) {
      targets.push({ key: 'avatar', label: this.msg.senderName, menu: false,
        x: p.avatar.x, y: p.avatar.y, width: p.avatar.width, height: p.avatar.height });
    }
    if (p.quote !== null) {
      targets.push({ key: 'reply', label: str('mb_reply') + ' ' + this.msg.replySenderName + ' ' + this.msg.replyText,
        menu: false, x: p.quoteRect.x, y: p.quoteRect.y, width: p.quoteRect.width, height: p.quoteRect.height });
    }
    for (const hit of p.caption?.hits ?? []) {
      if (!hit.accessible) { continue; }
      targets.push({ key: 'text:' + hit.key, label: hit.link.accessibilityLabel, menu: false,
        x: p.captionX + hit.x, y: p.captionY + hit.y, width: hit.widthVp, height: hit.heightVp });
    }
    for (const tile of p.tiles) {
      targets.push({ key: 'media:' + tile.key, label: str(tile.cell.isVideo ? 'mb_tap_play_video' : 'mb_open_photo'),
        menu: false, x: tile.x, y: tile.y, width: tile.width, height: tile.height });
    }
    const chrome = p.chrome;
    if (chrome?.content.forward !== null && chrome?.content.forward !== undefined) {
      targets.push({ key: 'forward', label: str('mb_forwarded_from', this.msg.forwardFrom), menu: false,
        x: chrome.forwardRect.x, y: chrome.forwardRect.y, width: chrome.forwardRect.width, height: chrome.forwardRect.height });
    }
    for (const chip of chrome?.reactions?.chips ?? []) {
      targets.push({ key: 'reaction:' + chip.key, selected: chip.reaction?.isChosen === true,
        label: chip.reaction !== null ? `${chip.reaction.emoji || str('reactions_custom_emoji')} ${chip.reaction.count}` : str('a11y_message_reactions'), menu: false,
        x: (chrome?.reactionsX ?? 0) + chip.x, y: (chrome?.reactionsY ?? 0) + chip.y, width: chip.width, height: chip.height });
    }
    if (chrome?.content.comments !== null && chrome?.content.comments !== undefined) {
      targets.push({ key: 'comments', label: plural('mb_comments_n', this.msg.commentCount, this.msg.commentCount), menu: false,
        x: chrome.commentsRect.x, y: chrome.commentsRect.y, width: chrome.commentsRect.width, height: chrome.commentsRect.height });
    }
    return targets;
  }
  private activate(target: DrawnSemanticTarget, event: ClickEvent): void {
    // The native accessibility click may be queued across a recycle/update.
    // Only a target of the currently published semantic snapshot can act.
    if (this.targets.indexOf(target) < 0) { return; }
    if (target.menu) { this.onMenu(); }
    else { this.onActivate(target.x + target.width / 2, target.y + target.height / 2, event); }
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.targets, (target: DrawnSemanticTarget) => {
        Row().width(target.width).height(target.height).position({ x: target.x, y: target.y })
          .accessibilityText(target.label).accessibilitySelected(target.selected === true).accessibilityLevel('yes')
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .onClick((event: ClickEvent): void => { this.activate(target, event); });
      }, (target: DrawnSemanticTarget): string => `${this.msg.rowId}:${target.key}` + (target.key.startsWith('reaction:') ? `:${target.label}:${target.selected}:${target.x}:${target.y}:${target.width}:${target.height}` : ''));
    }.width(this.plan?.width ?? 0).height(this.plan?.height ?? 0).accessibilityGroup(false);
  }
}
