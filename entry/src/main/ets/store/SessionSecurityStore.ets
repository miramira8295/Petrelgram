import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

export interface SessionSnapshot {
  response: TdObject;
  revision: number;
}

// 与TD运行时同生命周期，不跨账号共享。推送只提供摘要，操作ID仍取完整会话列表。
export class SessionSecurityStore {
  private client: TdClient;
  private closed: boolean = false;
  private revision: number = 0;
  private count: number = 0;
  private summaryKey: string = '';
  private listeners: Array<(count: number) => void> = [];
  private events: Array<() => void> = [];
  private off: () => void;
  private pending: Promise<SessionSnapshot> | null = null;

  constructor(client: TdClient) {
    this.client = client;
    this.off = client.onUpdate('updateUnconfirmedSession', (update: TdObject): void => {
      if (this.closed) { return; }
      const count = Math.max(0, (update['unconfirmed_session_count'] as number | undefined) ?? 0);
      const summary = update['session'] as TdObject | undefined;
      const key = `${count}/${summary === undefined || summary === null ? '' : JSON.stringify(summary)}`;
      if (key === this.summaryKey && count === this.count) { return; }
      this.summaryKey = key;
      this.revision++;
      this.publish(count);
      this.events.slice().forEach((listener: () => void): void => { listener(); });
    });
  }

  subscribe(listener: (count: number) => void): () => void {
    if (this.closed) { listener(0); return (): void => {}; }
    this.listeners.push(listener);
    listener(this.count);
    return (): void => { this.listeners = this.listeners.filter((item) => item !== listener); };
  }

  onChange(listener: () => void): () => void {
    if (this.closed) { return (): void => {}; }
    this.events.push(listener);
    return (): void => { this.events = this.events.filter((item) => item !== listener); };
  }

  isOpen(): boolean { return !this.closed; }
  isCurrent(snapshot: SessionSnapshot): boolean {
    return !this.closed && snapshot.revision === this.revision;
  }

  read(): Promise<SessionSnapshot> {
    if (this.closed) { return Promise.reject(new TdError(499, 'Session runtime closed')); }
    if (this.pending !== null) { return this.pending; }
    const revision = this.revision;
    const request = this.client.send({ '@type': 'getActiveSessions' }, 15000)
      .then((response: TdObject): SessionSnapshot => {
        if (response['@type'] !== 'sessions') { throw new TdError(500, 'Invalid sessions'); }
        const rows = (response['sessions'] as TdObject[] | undefined) ?? [];
        if (!rows.some((row: TdObject): boolean => row['is_current'] === true)) {
          throw new TdError(500, 'CURRENT_SESSION_MISSING');
        }
        const snapshot: SessionSnapshot = { response, revision };
        if (this.isCurrent(snapshot)) {
          this.publish(rows.filter((row: TdObject): boolean => row['is_unconfirmed'] === true && row['is_current'] !== true).length);
        }
        return snapshot;
      }).finally((): void => { this.pending = null; });
    this.pending = request;
    return request;
  }

  // UI与客户端身份均需有效；不重试写请求。请求前后使旧列表快照失效。
  async mutate(request: TdRequest, current: () => boolean): Promise<void> {
    if (this.closed || !current()) { throw new TdError(499, 'Session page closed'); }
    this.revision++;
    try {
      const result = await this.client.send(request, 15000);
      if (this.closed || !current()) { throw new TdError(499, 'Session page closed'); }
      if (result['@type'] !== 'ok') { throw new TdError(500, 'Invalid session result'); }
    } finally {
      this.revision++;
    }
  }

  private publish(count: number): void {
    if (this.count === count) { return; }
    this.count = count;
    this.listeners.slice().forEach((listener: (count: number) => void): void => { listener(count); });
  }

  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    this.revision++;
    this.off();
    this.publish(0);
    this.listeners = [];
    this.events = [];
    this.summaryKey = '';
  }
}
