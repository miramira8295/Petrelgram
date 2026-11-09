import { TdClient } from '../tdkit/TdClient';
import { GroupCallParticipantInfo, GroupCallVideoSource } from '../tdkit/GroupCallTypes';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

export type GroupCallParticipantsListener = (participants: GroupCallParticipantInfo[]) => void;

function encodedSourceGroups(videoInfo: TdObject): string {
  const groups = (videoInfo['source_groups'] as TdObject[] | undefined) ?? [];
  return groups.map((group: TdObject): string => {
    const semantics = (group['semantics'] as string | undefined) ?? '';
    const ids = ((group['source_ids'] as number[] | undefined) ?? []).join(',');
    return `${semantics}=${ids}`;
  }).join(';');
}

function senderKey(sender: TdObject): string {
  const type = (sender['@type'] as string | undefined) ?? 'unknown';
  if (type === 'messageSenderUser') {
    return `user:${(sender['user_id'] as number | undefined) ?? 0}`;
  }
  return `chat:${(sender['chat_id'] as number | undefined) ?? 0}`;
}

function senderId(sender: TdObject): number {
  return (sender['@type'] as string | undefined) === 'messageSenderUser'
    ? ((sender['user_id'] as number | undefined) ?? 0)
    : ((sender['chat_id'] as number | undefined) ?? 0);
}

function normalizedAudioSourceId(sourceId: number): number {
  return sourceId > 2147483647 ? sourceId - 4294967296 : sourceId;
}

function initialsOf(name: string): string {
  const parts = name.trim().split(' ').filter((part: string): boolean => part !== '');
  if (parts.length === 0) { return '?'; }
  if (parts.length === 1) { return parts[0].substring(0, 1).toUpperCase(); }
  return `${parts[0].substring(0, 1)}${parts[parts.length - 1].substring(0, 1)}`.toUpperCase();
}

// Owns TDLib's incremental participant updates. TDLib removes a participant
// by sending an empty `order`, so keeping this in a map avoids stale video
// subscriptions and duplicate rows when the same participant changes state.
export class GroupCallParticipantsStore {
  private static readonly REMOVAL_GRACE_MS: number = 1200;
  private client: TdClient;
  private groupCallId: number;
  private participants: Map<string, GroupCallParticipantInfo> = new Map();
  private pendingRemovals: Map<string, number> = new Map();
  private names: Map<string, string> = new Map();
  private resolvingNames: Set<string> = new Set();
  private listeners: GroupCallParticipantsListener[] = [];
  private offParticipant: (() => void) | null = null;
  private offGroupCall: (() => void) | null = null;
  private revisionSequence: number = 0;
  private reportedParticipantCount: number = -1;
  private recoveryTimer: number = -1;
  private disposed: boolean = false;

  constructor(client: TdClient, groupCallId: number) {
    this.client = client;
    this.groupCallId = groupCallId;
    this.offParticipant = client.onUpdate(
      'updateGroupCallParticipant', (update: TdObject): void => this.onParticipant(update)
    );
    this.offGroupCall = client.onUpdate(
      'updateGroupCall', (update: TdObject): void => this.onGroupCall(update)
    );
  }

  subscribe(listener: GroupCallParticipantsListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.snapshot());
    return (): void => {
      this.listeners = this.listeners.filter(
        (current: GroupCallParticipantsListener): boolean => current !== listener
      );
    };
  }

  async load(limit: number = 100): Promise<void> {
    const request: TdRequest = { '@type': 'loadGroupCallParticipants' };
    request['group_call_id'] = this.groupCallId;
    request['limit'] = limit;
    await this.client.send(request);
  }

  // The decoded PCM callback is the fastest and most reliable source of
  // speaking state. TDLib returns the sender for that SSRC, so apply the state
  // locally instead of waiting for a second update round-trip. This also
  // revives a participant whose audio SSRC changed during mute/unmute.
  applyAudioActivity(audioSourceId: number, speaking: boolean, sender?: TdObject): void {
    const normalizedSource = normalizedAudioSourceId(audioSourceId);
    let key = '';
    if (sender !== undefined) {
      key = senderKey(sender);
    } else {
      for (const candidate of this.participants.values()) {
        if (normalizedAudioSourceId(candidate.audioSourceId) === normalizedSource ||
          normalizedAudioSourceId(candidate.screenSharingAudioSourceId) === normalizedSource) {
          key = candidate.key;
          break;
        }
      }
    }
    if (key === '') { return; }
    let participant = this.participants.get(key);
    if (participant === undefined) {
      if (!speaking || sender === undefined) { return; }
      const type = (sender['@type'] as string | undefined) ?? '';
      const id = senderId(sender);
      const name = this.names.get(key) ??
        (type === 'messageSenderUser' ? str('cp_user_id', id) : str('gcp_channel_id', id));
      participant = {
        key,
        revision: ++this.revisionSequence,
        audioSourceId: normalizedSource,
        screenSharingAudioSourceId: 0,
        senderId: id,
        senderType: type,
        name,
        initials: initialsOf(name),
        colorSeed: id,
        order: `activity:${Date.now()}`,
        isCurrentUser: false,
        isSpeaking: true,
        isMuted: false,
        videoSources: []
      };
      this.participants.set(key, participant);
      this.resolveName(key, type, id);
    } else {
      const wasPrimarySource = normalizedAudioSourceId(participant.audioSourceId) === normalizedSource;
      const nextMuted = speaking ? false : participant.isMuted;
      const sources = participant.videoSources.map(
        (source: GroupCallVideoSource): GroupCallVideoSource => ({
          endpointId: source.endpointId,
          participantKey: source.participantKey,
          name: source.name,
          audioSourceId: source.isScreenSharing || wasPrimarySource
            ? source.audioSourceId : normalizedSource,
          sourceGroups: source.sourceGroups,
          isPaused: source.isPaused,
          isScreenSharing: source.isScreenSharing,
          isSpeaking: speaking,
          isMuted: nextMuted
        })
      );
      participant = {
        key: participant.key,
        revision: ++this.revisionSequence,
        audioSourceId: normalizedSource,
        screenSharingAudioSourceId: participant.screenSharingAudioSourceId,
        senderId: participant.senderId,
        senderType: participant.senderType,
        name: participant.name,
        initials: participant.initials,
        colorSeed: participant.colorSeed,
        order: participant.order,
        isCurrentUser: participant.isCurrentUser,
        isSpeaking: speaking,
        isMuted: nextMuted,
        videoSources: sources
      };
      this.participants.set(key, participant);
    }
    if (speaking) { this.cancelRemoval(key); }
    logI(
      `[GroupCallParticipants] PCM key=${key} source=${normalizedSource} speaking=${speaking}`
    );
    this.emit();
  }

  dispose(): void {
    this.disposed = true;
    if (this.offParticipant !== null) {
      this.offParticipant();
      this.offParticipant = null;
    }
    if (this.offGroupCall !== null) {
      this.offGroupCall();
      this.offGroupCall = null;
    }
    if (this.recoveryTimer !== -1) { clearTimeout(this.recoveryTimer); this.recoveryTimer = -1; }
    for (const timerId of this.pendingRemovals.values()) {
      if (timerId >= 0) { clearTimeout(timerId); }
    }
    this.pendingRemovals.clear();
    this.listeners = [];
    this.participants.clear();
    this.names.clear();
    this.resolvingNames.clear();
  }

  private onParticipant(update: TdObject): void {
    if ((update['group_call_id'] as number | undefined) !== this.groupCallId) { return; }
    const raw = update['participant'] as TdObject | undefined;
    if (raw === undefined) { return; }
    const sender = raw['participant_id'] as TdObject | undefined;
    if (sender === undefined) { return; }
    const key = senderKey(sender);
    const order = (raw['order'] as string | undefined) ?? '';
    if (order === '') {
      this.scheduleRemoval(key);
      return;
    }
    this.cancelRemoval(key);
    const type = (sender['@type'] as string | undefined) ?? '';
    const id = senderId(sender);
    const previous = this.participants.get(key);
    const fallback = type === 'messageSenderUser' ? str('cp_user_id', id) : str('gcp_channel_id', id);
    const name = this.names.get(key) ?? (previous !== undefined ? previous.name : fallback);
    const isSpeaking = (raw['is_speaking'] as boolean | undefined) ?? false;
    const isMuted = ((raw['is_muted_for_all_users'] as boolean | undefined) ?? false) ||
      ((raw['is_muted_for_current_user'] as boolean | undefined) ?? false);
    const audioSourceId = (raw['audio_source_id'] as number | undefined) ?? 0;
    const screenSharingAudioSourceId =
      (raw['screen_sharing_audio_source_id'] as number | undefined) ?? 0;
    const revision = ++this.revisionSequence;
    logI(
      `[GroupCallParticipants] update key=${key} revision=${revision} muted=${isMuted} ` +
      `speaking=${isSpeaking} audioSource=${audioSourceId} order=${order}`
    );
    const sources: GroupCallVideoSource[] = [];
    this.appendVideoSource(
      sources, raw['video_info'] as TdObject | undefined, key, name,
      audioSourceId, false, isSpeaking, isMuted
    );
    this.appendVideoSource(
      sources, raw['screen_sharing_video_info'] as TdObject | undefined, key, name,
      screenSharingAudioSourceId !== 0 ? screenSharingAudioSourceId : audioSourceId,
      true, isSpeaking, isMuted
    );
    this.participants.set(key, {
      key,
      revision,
      audioSourceId,
      screenSharingAudioSourceId,
      senderId: id,
      senderType: type,
      name,
      initials: initialsOf(name),
      colorSeed: id,
      order,
      isCurrentUser: (raw['is_current_user'] as boolean | undefined) ?? false,
      isSpeaking,
      isMuted,
      videoSources: sources
    });
    this.emit();
    this.resolveName(key, type, id);
  }

  private appendVideoSource(
    target: GroupCallVideoSource[], info: TdObject | undefined, participantKey: string,
    name: string, audioSourceId: number, screen: boolean, speaking: boolean, muted: boolean
  ): void {
    if (info === undefined) { return; }
    const endpointId = (info['endpoint_id'] as string | undefined) ?? '';
    if (endpointId === '') { return; }
    target.push({
      endpointId,
      participantKey,
      name: screen ? str('gcp_screen_of', name) : name,
      audioSourceId,
      sourceGroups: encodedSourceGroups(info),
      isPaused: (info['is_paused'] as boolean | undefined) ?? false,
      isScreenSharing: screen,
      isSpeaking: speaking,
      isMuted: muted
    });
  }

  private resolveName(key: string, type: string, id: number): void {
    if (id === 0 || this.names.has(key) || this.resolvingNames.has(key)) { return; }
    this.resolvingNames.add(key);
    const request: TdRequest = { '@type': type === 'messageSenderUser' ? 'getUser' : 'getChat' };
    if (type === 'messageSenderUser') {
      request['user_id'] = id;
    } else {
      request['chat_id'] = id;
    }
    this.client.send(request).then((object: TdObject): void => {
      this.resolvingNames.delete(key);
      if (this.disposed) { return; }
      let name = '';
      if (type === 'messageSenderUser') {
        const first = (object['first_name'] as string | undefined) ?? '';
        const last = (object['last_name'] as string | undefined) ?? '';
        name = `${first} ${last}`.trim();
      } else {
        name = (object['title'] as string | undefined) ?? '';
      }
      const old = this.participants.get(key);
      if (name === '') { return; }
      this.names.set(key, name);
      if (old === undefined || old.name === name) { return; }
      const sources = old.videoSources.map((source: GroupCallVideoSource): GroupCallVideoSource => ({
        endpointId: source.endpointId,
        participantKey: source.participantKey,
        name: source.isScreenSharing ? str('gcp_screen_of', name) : name,
        audioSourceId: source.audioSourceId,
        sourceGroups: source.sourceGroups,
        isPaused: source.isPaused,
        isScreenSharing: source.isScreenSharing,
        isSpeaking: source.isSpeaking,
        isMuted: source.isMuted
      }));
      this.participants.set(key, {
        key: old.key,
        revision: ++this.revisionSequence,
        audioSourceId: old.audioSourceId,
        screenSharingAudioSourceId: old.screenSharingAudioSourceId,
        senderId: old.senderId,
        senderType: old.senderType,
        name,
        initials: initialsOf(name),
        colorSeed: old.colorSeed,
        order: old.order,
        isCurrentUser: old.isCurrentUser,
        isSpeaking: old.isSpeaking,
        isMuted: old.isMuted,
        videoSources: sources
      });
      this.emit();
    }).catch((error: Error): void => {
      this.resolvingNames.delete(key);
      logE(`GroupCallParticipantsStore.resolveName(${key}): ${error.message}`);
    });
  }

  private snapshot(): GroupCallParticipantInfo[] {
    const rows = Array.from(this.participants.values());
    rows.sort((a: GroupCallParticipantInfo, b: GroupCallParticipantInfo): number => {
      if (a.order === b.order) { return a.key.localeCompare(b.key); }
      return a.order > b.order ? -1 : 1;
    });
    return rows;
  }

  private onGroupCall(update: TdObject): void {
    const groupCall = update['group_call'] as TdObject | undefined;
    if (groupCall === undefined ||
      (groupCall['id'] as number | undefined) !== this.groupCallId) { return; }
    this.reportedParticipantCount = (groupCall['participant_count'] as number | undefined) ??
      this.reportedParticipantCount;
    logI(
      `[GroupCallParticipants] count=${this.reportedParticipantCount} cached=${this.participants.size} ` +
      `pending=${this.pendingRemovals.size}`
    );
    this.reconcileRemovals();
    const isJoined = (groupCall['is_joined'] as boolean | undefined) ?? false;
    if (isJoined && this.reportedParticipantCount > this.participants.size) {
      this.scheduleRecoveryLoad();
    }
  }

  private scheduleRemoval(key: string): void {
    const participant = this.participants.get(key);
    if (participant === undefined) {
      logI(`[GroupCallParticipants] ignore removal for unknown key=${key}`);
      return;
    }
    this.cancelRemoval(key);

    // Telegram can briefly publish an empty order while a participant toggles
    // audio and immediately rejoins. Keep the identity alive during that gap so
    // ArkUI doesn't lose the row; the next non-empty update cancels this timer.
    const revision = ++this.revisionSequence;
    this.participants.set(key, {
      key: participant.key,
      revision,
      audioSourceId: participant.audioSourceId,
      screenSharingAudioSourceId: participant.screenSharingAudioSourceId,
      senderId: participant.senderId,
      senderType: participant.senderType,
      name: participant.name,
      initials: participant.initials,
      colorSeed: participant.colorSeed,
      order: participant.order,
      isCurrentUser: participant.isCurrentUser,
      isSpeaking: false,
      isMuted: true,
      videoSources: participant.videoSources.map(
        (source: GroupCallVideoSource): GroupCallVideoSource => ({
          endpointId: source.endpointId,
          participantKey: source.participantKey,
          name: source.name,
          audioSourceId: source.audioSourceId,
          sourceGroups: source.sourceGroups,
          isPaused: source.isPaused,
          isScreenSharing: source.isScreenSharing,
          isSpeaking: false,
          isMuted: true
        })
      )
    });
    logI(
      `[GroupCallParticipants] removal pending key=${key} revision=${revision} ` +
      `graceMs=${GroupCallParticipantsStore.REMOVAL_GRACE_MS}`
    );
    this.emit();

    const timerId = setTimeout((): void => {
      if (this.pendingRemovals.get(key) !== timerId) { return; }
      // Keep the participant cached if the authoritative group-call count says
      // they are still in the room. A later active update restores their exact
      // microphone state; a real leave decreases participant_count and is
      // reconciled below.
      this.pendingRemovals.set(key, -1);
      this.reconcileRemovals();
      if (this.pendingRemovals.has(key)) {
        logI(
          `[GroupCallParticipants] retained muted key=${key} ` +
          `count=${this.reportedParticipantCount} cached=${this.participants.size}`
        );
      }
    }, GroupCallParticipantsStore.REMOVAL_GRACE_MS);
    this.pendingRemovals.set(key, timerId);
    // Ask TDLib for a fresh page after the temporary removal. If the sender
    // immediately re-enabled their microphone, their new audio source arrives
    // either through this refresh or the PCM-to-sender mapping above.
    this.scheduleRecoveryLoad(true);
  }

  private cancelRemoval(key: string): void {
    const timerId = this.pendingRemovals.get(key);
    if (timerId === undefined) { return; }
    if (timerId >= 0) { clearTimeout(timerId); }
    this.pendingRemovals.delete(key);
    logI(`[GroupCallParticipants] removal cancelled by active update key=${key}`);
  }

  private reconcileRemovals(): void {
    if (this.reportedParticipantCount < 0) { return; }
    let excess = this.participants.size - this.reportedParticipantCount;
    if (excess <= 0) { return; }
    let changed = false;
    for (const key of this.pendingRemovals.keys()) {
      if (excess <= 0) { break; }
      const timerId = this.pendingRemovals.get(key);
      if (timerId !== undefined && timerId >= 0) { clearTimeout(timerId); }
      this.pendingRemovals.delete(key);
      if (this.participants.delete(key)) {
        excess -= 1;
        changed = true;
        logI(
          `[GroupCallParticipants] removed confirmed leaver key=${key} ` +
          `count=${this.reportedParticipantCount}`
        );
      }
    }
    if (changed) { this.emit(); }
  }

  private scheduleRecoveryLoad(force: boolean = false): void {
    if (this.recoveryTimer !== -1) { return; }
    this.recoveryTimer = setTimeout((): void => {
      this.recoveryTimer = -1;
      if (this.disposed || (!force && this.reportedParticipantCount <= this.participants.size)) { return; }
      logI(
        `[GroupCallParticipants] recovery load count=${this.reportedParticipantCount} ` +
        `cached=${this.participants.size}`
      );
      this.load(100).catch((error: Error): void => {
        logE(`[GroupCallParticipants] recovery load failed: ${error.message}`);
      });
    }, 300);
  }

  private emit(): void {
    const value = this.snapshot();
    for (const listener of this.listeners) { listener(value); }
  }
}
