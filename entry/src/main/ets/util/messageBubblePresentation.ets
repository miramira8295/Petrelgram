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

// 头像解出来的那一份东西：路径 + 带不带动画。**一个对象**而不是两个 @Local，
// 原因是 @ReusableV2 的复用重置按变量个数逐条赋值（见官方《@ReusableV2装饰器》
// 的重置表，以及转译产物 resetStateVarsOnReuse 里逐行 this.x = 初值），
// 两个变量就是两次"复位→重新播种"的往返，一次重渲染变成两三次。
export interface SenderAvatarState {
  path: string;
  animated: boolean;
}

// 复用重置用的初值。同一个模块级常量 = 同一个引用，复位到它时若已经是它，
// `@Local` 的 `===` 比较会直接短路，不产生通知。
export const EMPTY_SENDER_AVATAR_STATE: SenderAvatarState = { path: '', animated: false };

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
