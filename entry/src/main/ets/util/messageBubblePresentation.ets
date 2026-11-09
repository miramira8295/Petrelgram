// Narrow, immutable presentation inputs. Each cache belongs to one bubble or
// avatar slot, so recycling cannot accumulate entries for every visited sender.
export interface SenderAvatarSpec {
  senderId: number;
  senderIsUser: boolean;
  initialPath: string;
  initials: string;
  avatarSize: number;
  animate: boolean;
}

export class SenderAvatarSpecCache {
  private previous: SenderAvatarSpec | undefined = undefined;

  prepare(senderId: number, senderIsUser: boolean, initialPath: string,
    initials: string, avatarSize: number, animate: boolean): SenderAvatarSpec {
    const previous = this.previous;
    if (previous !== undefined && previous.senderId === senderId &&
      previous.senderIsUser === senderIsUser && previous.initialPath === initialPath &&
      previous.initials === initials && previous.avatarSize === avatarSize &&
      previous.animate === animate) {
      return previous;
    }
    const next: SenderAvatarSpec = { senderId, senderIsUser, initialPath, initials, avatarSize, animate };
    this.previous = next;
    return next;
  }
}

export class BubbleCornerCache {
  private radius: number = 0;
  private outgoing: boolean = false;
  private showSenderName: boolean = false;
  private showAvatar: boolean = false;
  private previous: BorderRadiuses | undefined = undefined;

  prepare(radius: number, outgoing: boolean, showSenderName: boolean,
    showAvatar: boolean): BorderRadiuses {
    if (this.previous !== undefined && this.radius === radius && this.outgoing === outgoing &&
      this.showSenderName === showSenderName && this.showAvatar === showAvatar) {
      return this.previous;
    }
    const run: number = Math.min(radius, 7);
    const top: number = showSenderName ? radius : run;
    const bottom: number = showAvatar ? radius : run;
    const next: BorderRadiuses = {
      topLeft: outgoing ? radius : top,
      topRight: outgoing ? top : radius,
      bottomLeft: outgoing ? radius : bottom,
      bottomRight: outgoing ? bottom : radius
    };
    this.radius = radius;
    this.outgoing = outgoing;
    this.showSenderName = showSenderName;
    this.showAvatar = showAvatar;
    this.previous = next;
    return next;
  }
}
