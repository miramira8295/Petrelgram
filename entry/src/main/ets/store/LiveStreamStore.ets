import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { GroupCallStreamInfo, LiveStreamState, emptyLiveStreamState } from '../tdkit/GroupCallTypes';

export class LiveStreamStore {
  private client: TdClient;
  private groupCallId: number;
  private state: LiveStreamState = emptyLiveStreamState();
  private listeners: Array<(s: LiveStreamState) => void> = [];
  private unsub: (() => void) | null = null;

  constructor(client: TdClient, groupCallId: number) {
    this.client = client;
    this.groupCallId = groupCallId;
    this.unsub = this.client.onUpdate('updateGroupCall', (u: TdObject) => this.onGroupCall(u));
  }

  getState(): LiveStreamState {
    return this.state;
  }

  subscribe(l: (s: LiveStreamState) => void): () => void {
    this.listeners = [...this.listeners, l];
    return (): void => {
      this.listeners = this.listeners.filter((x: (s: LiveStreamState) => void) => x !== l);
    };
  }

  setStreams(streams: GroupCallStreamInfo[]): void {
    this.state = {
      title: this.state.title,
      isActive: this.state.isActive,
      isRtmpStream: this.state.isRtmpStream,
      isJoined: true,
      needRejoin: false,
      canSendMessages: this.state.canSendMessages,
      areMessagesAllowed: this.state.areMessagesAllowed,
      participantCount: this.state.participantCount,
      streams,
      error: ''
    };
    this.emit();
  }

  applyGroupCall(groupCall: TdObject): void {
    if (((groupCall['id'] as number | undefined) ?? 0) !== this.groupCallId) { return; }
    this.state = {
      title: (groupCall['title'] as string | undefined) ?? this.state.title,
      isActive: (groupCall['is_active'] as boolean | undefined) ?? false,
      isRtmpStream: (groupCall['is_rtmp_stream'] as boolean | undefined) ?? this.state.isRtmpStream,
      isJoined: (groupCall['is_joined'] as boolean | undefined) ?? false,
      needRejoin: (groupCall['need_rejoin'] as boolean | undefined) ?? false,
      canSendMessages: (groupCall['can_send_messages'] as boolean | undefined) ?? false,
      areMessagesAllowed: (groupCall['are_messages_allowed'] as boolean | undefined) ?? false,
      participantCount: (groupCall['participant_count'] as number | undefined) ?? 0,
      streams: this.state.streams,
      error: ''
    };
    this.emit();
  }

  dispose(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    this.listeners = [];
  }

  private onGroupCall(update: TdObject): void {
    const gc = update['group_call'] as TdObject | undefined;
    if (gc === undefined || (gc['id'] as number | undefined) !== this.groupCallId) {
      return;
    }
    this.applyGroupCall(gc);
  }

  private emit(): void {
    for (const l of this.listeners) { l(this.state); }
  }
}
