import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { GroupCallStreamInfo } from '../tdkit/GroupCallTypes';
import { getGroupCallStreamSegment } from '../tdkit/GroupCallApi';
import { startOffset } from './StreamSegmentMath';
import { logI, logW } from '../util/log';

// Phase 0 probe (diagnostic). Adds a MINIMAL-PAYLOAD join attempt: the empty
// payload was rejected only for being empty, so we now send a syntactically
// valid (but fake) tgcalls-style payload to see if TDLib lets us join and
// then reach the stream/segment APIs — without a real WebRTC/DTLS handshake.
const PROBE_TIMEOUT_MS: number = 30000;

async function sendRaw(client: TdClient, req: TdRequest, tag: string): Promise<TdObject | null> {
  try {
    return await client.send(req, PROBE_TIMEOUT_MS);
  } catch (e) {
    logW(`[Phase0] ${tag} failed: ${e}`);
    return null;
  }
}

function randHex(bytes: number): string {
  let s = '';
  for (let i = 0; i < bytes; i++) {
    const b = Math.floor(Math.random() * 256);
    s += b.toString(16).padStart(2, '0');
  }
  return s;
}

// 32-byte sha-256-shaped fingerprint: "AB:CD:..." (fake but well-formed)
function fakeFingerprint(): string {
  const parts: string[] = [];
  for (let i = 0; i < 32; i++) {
    parts.push(Math.floor(Math.random() * 256).toString(16).padStart(2, '0').toUpperCase());
  }
  return parts.join(':');
}

function buildMinimalPayload(ssrc: number): string {
  const fp: Record<string, string> = { 'hash': 'sha-256', 'setup': 'active', 'fingerprint': fakeFingerprint() };
  const payload: Record<string, Object> = {
    'ufrag': randHex(4),
    'pwd': randHex(16),
    'fingerprints': [fp] as Object,
    'ssrc': ssrc as Object
  };
  return JSON.stringify(payload);
}

function parseStreams(resp: TdObject | null): GroupCallStreamInfo[] {
  if (resp === null) { return []; }
  const raw = (resp['streams'] as TdObject[] | undefined) ?? [];
  return raw.map((s: TdObject): GroupCallStreamInfo => ({
    channelId: (s['channel_id'] as number | undefined) ?? 0,
    scale: (s['scale'] as number | undefined) ?? 0,
    timeOffset: (s['time_offset'] as number | undefined) ?? 0
  }));
}

async function fetchStreams(client: TdClient, groupCallId: number, tag: string): Promise<GroupCallStreamInfo[]> {
  const req: TdRequest = { '@type': 'getGroupCallStreams' };
  req['group_call_id'] = groupCallId;
  const resp = await sendRaw(client, req, `${tag} getGroupCallStreams`);
  const streams = parseStreams(resp);
  logI(`[Phase0] ${tag} streams=${JSON.stringify(streams)}`);
  return streams;
}

async function trySegment(client: TdClient, groupCallId: number, streams: GroupCallStreamInfo[]): Promise<void> {
  if (streams.length === 0) { logW('[Phase0] no streams -> skip segment'); return; }
  const s: GroupCallStreamInfo = streams[0];
  const probeOffset: number = startOffset(s.timeOffset, s.scale, 2);
  try {
    const seg: Uint8Array = await getGroupCallStreamSegment(
      client, groupCallId, probeOffset, s.scale, s.channelId, 'groupCallVideoQualityThumbnail'
    );
    logI(`[Phase0] segment ok len=${seg.length} first16=${JSON.stringify(Array.from(seg.slice(0, 16)))}`);
  } catch (e) {
    logW(`[Phase0] segment failed: ${e}`);
  }
}

export async function runLiveStreamProbe(client: TdClient, groupCallId: number): Promise<void> {
  logI(`[Phase0] probe start gcid=${groupCallId}`);
  if (groupCallId <= 0) { logW('[Phase0] invalid gcid, abort'); return; }

  const gcReq: TdRequest = { '@type': 'getGroupCall' };
  gcReq['group_call_id'] = groupCallId;
  const gc = await sendRaw(client, gcReq, 'getGroupCall');
  if (gc !== null) {
    logI(`[Phase0] getGroupCall ok: is_rtmp=${gc['is_rtmp_stream']} active=${gc['is_active']} joined=${gc['is_joined']} participants=${gc['participant_count']}`);
  }

  // Step A: streams without joining
  let streams = await fetchStreams(client, groupCallId, 'NO-JOIN');
  if (streams.length > 0) { await trySegment(client, groupCallId, streams); return; }

  // Step B: join with a MINIMAL (fake but well-formed) tgcalls-style payload
  const ssrc = Math.floor(Math.random() * 2000000000) + 1;
  const payload = buildMinimalPayload(ssrc);
  const params: TdObject = { '@type': 'groupCallJoinParameters' };
  params['audio_source_id'] = ssrc;
  params['payload'] = payload;
  params['is_muted'] = true;
  params['is_my_video_enabled'] = false;
  const joinReqObj: Record<string, Object | null> = { '@type': 'joinVideoChat' };
  joinReqObj['group_call_id'] = groupCallId;
  joinReqObj['participant_id'] = null;
  joinReqObj['join_parameters'] = params;
  joinReqObj['invite_hash'] = '';
  const joinResp = await sendRaw(client, joinReqObj as TdRequest, 'joinVideoChat(minimal payload)');
  if (joinResp === null) {
    logW('[Phase0] minimal-payload join did not succeed; cannot reach stream after join');
    return;
  }
  const respText = (joinResp['text'] as string | undefined) ?? '';
  logI(`[Phase0] joinVideoChat(minimal payload) ACCEPTED response_len=${respText.length} resp_head=${respText.substring(0, 80)}`);

  // Step C: after join, retry streams + segment
  streams = await fetchStreams(client, groupCallId, 'POST-JOIN');
  await trySegment(client, groupCallId, streams);
}
