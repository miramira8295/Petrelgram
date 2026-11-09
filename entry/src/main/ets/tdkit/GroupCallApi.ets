import util from '@ohos.util';
import { TdClient } from './TdClient';
import { TdObject, TdRequest } from './TdTypes';
import { GroupCallStreamInfo } from './GroupCallTypes';

// SSRCs are unsigned in WebRTC, while TDLib exposes them as int32. Keep the
// exact lower 32 bits when crossing the JSON API boundary; otherwise sources
// above INT32_MAX can't be resolved back to their participant.
function tdAudioSourceId(sourceId: number): number {
  return sourceId > 2147483647 ? sourceId - 4294967296 : sourceId;
}

export async function getGroupCall(client: TdClient, groupCallId: number): Promise<TdObject> {
  const req: TdRequest = { '@type': 'getGroupCall' };
  req['group_call_id'] = groupCallId;
  return client.send(req);
}

export async function createVideoChat(
  client: TdClient, chatId: number, isRtmpStream: boolean
): Promise<number> {
  const req: TdRequest = { '@type': 'createVideoChat' };
  req['chat_id'] = chatId;
  req['title'] = '';
  req['start_date'] = 0;
  req['is_rtmp_stream'] = isRtmpStream;
  const response = await client.send(req);
  return (response['id'] as number | undefined) ??
    ((response['group_call_id'] as number | undefined) ?? 0);
}

export async function startScheduledVideoChat(
  client: TdClient, groupCallId: number
): Promise<void> {
  const req: TdRequest = { '@type': 'startScheduledVideoChat' };
  req['group_call_id'] = groupCallId;
  await client.send(req);
}

export async function getGroupCallStreams(client: TdClient, groupCallId: number): Promise<GroupCallStreamInfo[]> {
  const req: TdRequest = { '@type': 'getGroupCallStreams' };
  req['group_call_id'] = groupCallId;
  const resp = await client.send(req);
  const raw = (resp['streams'] as TdObject[] | undefined) ?? [];
  return raw.map((s: TdObject): GroupCallStreamInfo => ({
    channelId: (s['channel_id'] as number | undefined) ?? 0,
    scale: (s['scale'] as number | undefined) ?? 0,
    timeOffset: (s['time_offset'] as number | undefined) ?? 0
  }));
}

export async function joinVideoChat(
  client: TdClient, groupCallId: number, audioSourceId: number, payload: string, isMuted: boolean
): Promise<string> {
  const params: TdObject = { '@type': 'groupCallJoinParameters' };
  params['audio_source_id'] = tdAudioSourceId(audioSourceId);
  params['payload'] = payload;
  params['is_muted'] = isMuted;
  params['is_my_video_enabled'] = false;
  const reqObj: Record<string, Object | null> = { '@type': 'joinVideoChat' };
  reqObj['group_call_id'] = groupCallId;
  reqObj['participant_id'] = null; // 以自身加入
  reqObj['join_parameters'] = params;
  reqObj['invite_hash'] = '';
  const req = reqObj as TdRequest;
  const resp = await client.send(req);
  return (resp['text'] as string | undefined) ?? '';
}

export async function toggleGroupCallIsMyVideoEnabled(
  client: TdClient, groupCallId: number, enabled: boolean
): Promise<void> {
  const req: TdRequest = { '@type': 'toggleGroupCallIsMyVideoEnabled' };
  req['group_call_id'] = groupCallId;
  req['is_my_video_enabled'] = enabled;
  await client.send(req);
}

export async function startGroupCallScreenSharing(
  client: TdClient, groupCallId: number, audioSourceId: number, payload: string
): Promise<string> {
  const req: TdRequest = { '@type': 'startGroupCallScreenSharing' };
  req['group_call_id'] = groupCallId;
  req['audio_source_id'] = tdAudioSourceId(audioSourceId);
  req['payload'] = payload;
  const response = await client.send(req);
  return (response['text'] as string | undefined) ?? '';
}

export async function endGroupCallScreenSharing(
  client: TdClient, groupCallId: number
): Promise<void> {
  const req: TdRequest = { '@type': 'endGroupCallScreenSharing' };
  req['group_call_id'] = groupCallId;
  await client.send(req);
}

export async function getGroupCallStreamSegment(
  client: TdClient, groupCallId: number, timeOffset: number, scale: number, channelId: number, videoQualityType: string
): Promise<Uint8Array> {
  const quality: TdObject = { '@type': videoQualityType };
  const reqObject: Record<string, Object | null> = { '@type': 'getGroupCallStreamSegment' };
  reqObject['group_call_id'] = groupCallId;
  reqObject['time_offset'] = timeOffset;
  reqObject['scale'] = scale;
  reqObject['channel_id'] = channelId;
  // TDLib requires null for mixed-audio chunks. Supplying even thumbnail
  // quality switches the request to the video-segment path.
  reqObject['video_quality'] = videoQualityType === '' ? null : quality;
  const req = reqObject as TdRequest;
  const resp = await client.send(req, 60000);
  const b64 = (resp['data'] as string | undefined) ?? '';
  const helper = new util.Base64Helper();
  return b64 === '' ? new Uint8Array(0) : helper.decodeSync(b64);
}

export async function leaveGroupCall(client: TdClient, groupCallId: number): Promise<void> {
  const req: TdRequest = { '@type': 'leaveGroupCall' };
  req['group_call_id'] = groupCallId;
  await client.send(req);
}

export async function endGroupCall(client: TdClient, groupCallId: number): Promise<void> {
  const req: TdRequest = { '@type': 'endGroupCall' };
  req['group_call_id'] = groupCallId;
  await client.send(req);
}

export async function toggleGroupCallParticipantIsMuted(
  client: TdClient, groupCallId: number, participantId: TdObject, isMuted: boolean
): Promise<void> {
  const req: TdRequest = { '@type': 'toggleGroupCallParticipantIsMuted' };
  req['group_call_id'] = groupCallId;
  req['participant_id'] = participantId;
  req['is_muted'] = isMuted;
  await client.send(req);
}

// tgcalls detects activity from decoded PCM. TDLib uses this notification to
// associate an audio SSRC with a participant and publish is_speaking updates.
export async function setGroupCallParticipantIsSpeaking(
  client: TdClient, groupCallId: number, audioSourceId: number, isSpeaking: boolean
): Promise<TdObject> {
  const req: TdRequest = { '@type': 'setGroupCallParticipantIsSpeaking' };
  req['group_call_id'] = groupCallId;
  req['audio_source'] = tdAudioSourceId(audioSourceId);
  req['is_speaking'] = isSpeaking;
  return client.send(req);
}
