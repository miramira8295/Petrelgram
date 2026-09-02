import { mirrorChatEnvKey } from './chatEnvMirror';
// 消息里的 t.me 链接点下去之后要往返一次服务器（getMessageLinkInfo /
// searchPublicChat / getInternalLinkType）才知道该开哪一页。网络一慢，
// 用户看不到任何反馈，自然会再点——于是同一个群被开出好几层。
//
// 这里管两件事：解析在飞的时候挡住后续点击，并把"正在解析的那个 url"
// 广播出去，让被点的那段文字能自己表现出加载中。
//
// 单飞是全局的而不是按 url 的：解析期间点另一个链接同样要挡，否则两个
// 链接会并排推两层页面。

// 时钟从外面传进来，闸门本身没有时间概念——这样看门狗的行为可以单测，
// 不用真的等十几秒。
export class LinkTapGate {
  // 解析的下游有十来条分支，其中若干条既不跳页也不回调就结束了。没有
  // 看门狗，那样一次解析会把所有链接永久锁死。
  static readonly WATCHDOG_MS: number = 10_000;

  private url: string = '';
  private startedAt: number = 0;

  busyUrl(): string {
    return this.url;
  }

  // 放行返回 true，挡住返回 false。now 是调用方的单调时钟读数。
  begin(url: string, now: number): boolean {
    if (this.url !== '' && now - this.startedAt < LinkTapGate.WATCHDOG_MS) {
      return false;
    }
    this.url = url;
    this.startedAt = now;
    return true;
  }

  end(): void {
    this.url = '';
    this.startedAt = 0;
  }

  // 只关掉自己那一次。收尾比下一次点击来得晚时，用它避免误伤。
  endIf(url: string): void {
    if (this.url === url) {
      this.end();
    }
  }
}

const gate: LinkTapGate = new LinkTapGate();

// 被点中的链接 url，供 MessageBubble 把那段文字画成加载中。空串表示空闲。
export const LINK_NAV_BUSY_KEY: string = 'linkNavBusyUrl';

function publish(): void {
  AppStorage.setOrCreate(LINK_NAV_BUSY_KEY, gate.busyUrl());
  mirrorChatEnvKey(LINK_NAV_BUSY_KEY, gate.busyUrl());
}

export function beginLinkNav(url: string): boolean {
  const admitted = gate.begin(url, Date.now());
  if (admitted) {
    publish();
  }
  return admitted;
}

export function endLinkNav(): void {
  gate.end();
  publish();
}

export function endLinkNavIf(url: string): void {
  gate.endIf(url);
  publish();
}

export function linkNavBusyUrl(): string {
  return gate.busyUrl();
}
