import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { TdClient } from '../tdkit/TdClient';
interface RichLoadJob { id: number; resolve: (value: TdObject) => void; reject: (error: Error) => void; }
// Only visible incomplete messages request full content. FIFO cursor is O(1)
// amortized; at most four native requests, with no list scan per response.
export class RichMessageFullLoader {
  private client: TdClient;
  private chatId: number;
  private active: number = 0;
  private closed: boolean = false;
  private queue: RichLoadJob[] = [];
  private cursor: number = 0;
  private jobs: Map<number, Promise<TdObject>> = new Map();
  constructor(client: TdClient, chatId: number) { this.client = client; this.chatId = chatId; }
  load(id: number): Promise<TdObject> {
    const hit = this.jobs.get(id); if (hit !== undefined) { return hit; }
    if (this.closed) { return Promise.reject(new Error('RICH_MESSAGE_LOAD_CLOSED')); }
    const work = new Promise<TdObject>((resolve, reject): void => { this.queue.push({ id, resolve, reject }); });
    this.jobs.set(id, work); this.pump(); return work;
  }
  private pump(): void {
    while (!this.closed && this.active < 4 && this.cursor < this.queue.length) {
      const job = this.queue[this.cursor++]; this.active++;
      const request: TdRequest = { '@type': 'getFullRichMessage' };
      request['chat_id'] = this.chatId; request['message_id'] = job.id;
      this.client.send(request).then((result: TdObject): void => {
        if (this.closed) { job.reject(new Error('RICH_MESSAGE_LOAD_CLOSED')); } else { job.resolve(result); }
      }, (error: Error): void => job.reject(error)).finally((): void => {
        this.jobs.delete(job.id); this.active--; this.pump();
      });
    }
    if (this.cursor === this.queue.length) { this.queue = []; this.cursor = 0; }
    else if (this.cursor >= 256 && this.cursor * 2 >= this.queue.length) { this.queue = this.queue.slice(this.cursor); this.cursor = 0; }
  }
  close(): void {
    this.closed = true;
    for (let i = this.cursor; i < this.queue.length; i++) {
      const job = this.queue[i]; this.jobs.delete(job.id); job.reject(new Error('RICH_MESSAGE_LOAD_CLOSED'));
    }
    this.queue = []; this.cursor = 0;
  }
}
