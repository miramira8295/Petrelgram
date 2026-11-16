import { MessageEntry } from '../store/MessageEntry';

// One owner per chat page. Pass the reference through list hosts without
// reading nowSec there; only consumers that display time subscribe to ticks.
@ObservedV2
export class MessageRowClock {
  @Trace nowSec: number = 0;
}

export function messageRowNeedsClock(msg: MessageEntry): boolean {
  // Outgoing menus retain their editable-time boundary. Location and poll
  // consumers decide whether their countdown has ended; don't freeze them.
  return msg.isOutgoing || msg.contentType === 'location' ||
    msg.contentType === 'venue' || msg.contentType === 'poll';
}
