// 对方操作状态：页面实例各自持有。仅在最早状态到期时唤醒，不做常驻轮询。
import { TdObject } from '../../tdkit/TdTypes';
import { getUserStore } from '../../tdkit/Globals';
import { TypingAction, applyTypingUpdate, pruneExpiredTyping, chatActionLabelOf } from '../../util/typingIndicator';

export interface TypingIndicatorHost {
  chatId: () => number;
  threadRootId: () => number;
  forumTopicId: () => number;
  directMessagesTopicId: () => number;
  currentKind: () => string;
}

// 隔离资料查询与计时环境，单测无需未初始化的全局单例或真实等待。
export interface TypingIndicatorDependencies {
  now: () => number;
  ensureUser: (uid: number) => void;
  displayName: (uid: number) => string;
  schedule: (callback: () => void, delay: number) => number;
  cancel: (timer: number) => void;
}

@ObservedV2
export class TypingIndicatorState {
  @Trace label: string = '';
  private senders: Map<number, TypingAction> = new Map();
  private timer: number = -1;
  private generation: number = 0;
  private active: boolean = true;
  private disposed: boolean = false;
  private scope: string = '';
  private host: TypingIndicatorHost = {
    chatId: (): number => 0,
    threadRootId: (): number => 0,
    forumTopicId: (): number => 0,
    directMessagesTopicId: (): number => 0,
    currentKind: (): string => ''
  };
  private deps: TypingIndicatorDependencies;

  constructor(deps?: TypingIndicatorDependencies) {
    this.deps = deps ?? {
      now: (): number => Date.now(),
      ensureUser: (uid: number): void => { getUserStore().ensure(uid); },
      displayName: (uid: number): string => getUserStore().displayName(uid),
      schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
      cancel: (timer: number): void => { clearTimeout(timer); }
    };
  }

  bind(host: TypingIndicatorHost): void {
    this.clear();
    this.host = host;
    this.scope = this.currentScope();
    this.disposed = false;
  }

  setActive(active: boolean): void {
    if (this.active === active) { return; }
    this.active = active;
    if (!active) { this.clear(); }
  }

  private currentScope(): string {
    return `${this.host.chatId()}/${this.host.threadRootId()}/${this.host.forumTopicId()}/${this.host.directMessagesTopicId()}`;
  }

  private syncScope(): void {
    const scope = this.currentScope();
    if (scope !== this.scope) {
      this.clear();
      this.scope = scope;
    }
  }

  onChatAction(update: TdObject): void {
    if (this.disposed || !this.active) { return; }
    this.syncScope();
    const now = this.deps.now();
    const expired = pruneExpiredTyping(this.senders, now);
    const uid = applyTypingUpdate(this.senders, update, now, this.host.chatId(),
      this.host.threadRootId(), this.host.forumTopicId(), this.host.directMessagesTopicId());
    if (uid === 0 && !expired) { return; }
    if (uid > 0 && this.senders.has(uid)) { this.deps.ensureUser(uid); }
    this.refreshLabel();
    this.armExpiry();
  }

  // UserStore 先处理 updateUser；姓名补齐后更新当前提示，不必等对方再次输入。
  onUserUpdate(update: TdObject): void {
    if (this.disposed || !this.active) { return; }
    this.syncScope();
    const user = update['user'] as TdObject | undefined;
    const uid = (user?.['id'] as number | undefined) ?? 0;
    if (this.senders.has(uid)) {
      pruneExpiredTyping(this.senders, this.deps.now());
      this.refreshLabel();
      this.armExpiry();
    }
  }

  private refreshLabel(): void {
    const label = chatActionLabelOf(this.host.currentKind(), this.senders, this.deps.displayName);
    if (label !== this.label) { this.label = label; }
  }

  private stopTimer(): void {
    this.generation++;
    if (this.timer !== -1) { this.deps.cancel(this.timer); this.timer = -1; }
  }

  private armExpiry(): void {
    this.stopTimer();
    if (this.senders.size === 0) { return; }
    let next = Number.MAX_SAFE_INTEGER;
    this.senders.forEach((action: TypingAction): void => { next = Math.min(next, action.expiresAt); });
    const generation = this.generation;
    this.timer = this.deps.schedule((): void => {
      if (generation !== this.generation || this.disposed || !this.active) { return; }
      this.timer = -1;
      this.syncScope();
      pruneExpiredTyping(this.senders, this.deps.now());
      this.refreshLabel();
      this.armExpiry();
    }, Math.max(1, next - this.deps.now()));
  }

  private clear(): void {
    this.stopTimer();
    this.senders.clear();
    if (this.label !== '') { this.label = ''; }
  }

  dispose(): void {
    this.disposed = true;
    this.clear();
  }
}
