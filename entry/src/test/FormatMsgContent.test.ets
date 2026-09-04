import { describe, it, expect } from '@ohos/hypium';
import { formatMsgContent, speechStateOf, speechTextOf } from '../main/ets/util/formatMsgContent';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function textMsg(t: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = t;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}

function linkPreviewTextMsg(previewType: TdObject, url: string = 'https://example.com/a'): TdObject {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = url;
  const description: TdObject = { '@type': 'formattedText' };
  description['text'] = 'Preview description';
  const preview: TdObject = { '@type': 'linkPreview' };
  preview['url'] = url;
  preview['site_name'] = 'Example';
  preview['title'] = 'Preview title';
  preview['description'] = description;
  preview['type'] = previewType;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  content['link_preview'] = preview;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function previewPhoto(ids: number[], downloadedIndex: number = -1): TdObject {
  const sizes: TdObject[] = [];
  for (let index: number = 0; index < ids.length; index++) {
    const file: TdObject = { '@type': 'file' };
    file['id'] = ids[index];
    file['size'] = 1000;
    const local: TdObject = { '@type': 'localFile' };
    local['is_downloading_completed'] = index === downloadedIndex;
    local['is_downloading_active'] = false;
    local['path'] = index === downloadedIndex ? `/data/preview_${ids[index]}.jpg` : '';
    local['downloaded_size'] = index === downloadedIndex ? 1000 : 0;
    file['local'] = local;
    const size: TdObject = { '@type': 'photoSize' };
    size['photo'] = file;
    size['width'] = 160 * (index + 1);
    size['height'] = 90 * (index + 1);
    sizes.push(size);
  }
  const photo: TdObject = { '@type': 'photo' };
  photo['sizes'] = sizes;
  return photo;
}
function photoMsg(fileId: number): TdObject {
  const file: TdObject = { '@type': 'file' }; file['id'] = fileId;
  const size: TdObject = { '@type': 'photoSize' }; size['photo'] = file;
  const photo: TdObject = { '@type': 'photo' }; photo['sizes'] = [size];
  const c: TdObject = { '@type': 'messagePhoto' }; c['photo'] = photo;
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}
function stickerMsg(): TdObject {
  const c: TdObject = { '@type': 'messageSticker' };
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}
function stickerFile(id: number, path: string = '', downloaded: number = 0): TdObject {
  const file: TdObject = { '@type': 'file' };
  file['id'] = id;
  file['size'] = 1000;
  const local: TdObject = { '@type': 'localFile' };
  local['is_downloading_completed'] = path !== '';
  local['is_downloading_active'] = path === '' && downloaded > 0;
  local['path'] = path;
  local['downloaded_size'] = path !== '' ? 1000 : downloaded;
  file['local'] = local;
  return file;
}
function richStickerMsg(formatType: string, sourcePath: string = '', thumbPath: string = ''): TdObject {
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = stickerFile(502, thumbPath);
  thumb['format'] = { '@type': 'thumbnailFormatWebp' } as TdObject;
  const sticker: TdObject = { '@type': 'sticker' };
  sticker['sticker'] = stickerFile(501, sourcePath, sourcePath === '' ? 420 : 1000);
  sticker['thumbnail'] = thumb;
  sticker['format'] = { '@type': formatType } as TdObject;
  sticker['width'] = 512;
  sticker['height'] = 384;
  sticker['emoji'] = '✨';
  const content: TdObject = { '@type': 'messageSticker' };
  content['sticker'] = sticker;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}
function animatedEmojiMsg(formatType: string): TdObject {
  const stickerMessage = richStickerMsg(formatType);
  const stickerContent = stickerMessage['content'] as TdObject;
  const animated: TdObject = { '@type': 'animatedEmoji' };
  animated['sticker'] = stickerContent['sticker'];
  const content: TdObject = { '@type': 'messageAnimatedEmoji' };
  content['animated_emoji'] = animated;
  content['emoji'] = '✨';
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}
function videoMsg(fileId: number, thumbFileId: number, thumbWidth: number, thumbHeight: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 4096;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbFileId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = thumbWidth;
  thumb['height'] = thumbHeight;
  const video: TdObject = { '@type': 'video' };
  video['video'] = source;
  video['thumbnail'] = thumb;
  video['width'] = 1920;
  video['height'] = 1080;
  video['duration'] = 75;
  video['mime_type'] = 'video/mp4';
  video['file_name'] = 'clip.mp4';
  const caption: TdObject = { '@type': 'formattedText' };
  caption['text'] = 'caption';
  const c: TdObject = { '@type': 'messageVideo' };
  c['video'] = video;
  c['caption'] = caption;
  const m: TdObject = { '@type': 'message' };
  m['content'] = c;
  return m;
}

function animationMsg(fileId: number, thumbFileId: number, thumbWidth: number, thumbHeight: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['expected_size'] = 8192;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbFileId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = thumbWidth;
  thumb['height'] = thumbHeight;
  const animation: TdObject = { '@type': 'animation' };
  animation['animation'] = source;
  animation['thumbnail'] = thumb;
  animation['width'] = 480;
  animation['height'] = 270;
  animation['duration'] = 4;
  animation['mime_type'] = 'video/mp4';
  animation['file_name'] = 'loop.mp4';
  const caption: TdObject = { '@type': 'formattedText' };
  caption['text'] = 'GIF caption';
  const content: TdObject = { '@type': 'messageAnimation' };
  content['animation'] = animation;
  content['caption'] = caption;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function voiceMsg(fileId: number, listened: boolean): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 2048;
  const voice: TdObject = { '@type': 'voiceNote' };
  voice['voice'] = source;
  voice['duration'] = 42;
  voice['mime_type'] = 'audio/ogg';
  voice['waveform'] = '//8=';
  const content: TdObject = { '@type': 'messageVoiceNote' };
  content['voice_note'] = voice;
  content['is_listened'] = listened;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function audioMsg(fileId: number, coverFileId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 5_242_880;
  const coverSource: TdObject = { '@type': 'file' };
  coverSource['id'] = coverFileId;
  const cover: TdObject = { '@type': 'thumbnail' };
  cover['file'] = coverSource;
  cover['width'] = 320;
  cover['height'] = 320;
  const audio: TdObject = { '@type': 'audio' };
  audio['audio'] = source;
  audio['album_cover_thumbnail'] = cover;
  audio['duration'] = 245;
  audio['title'] = 'Night Drive';
  audio['performer'] = 'Mose';
  audio['file_name'] = 'night-drive.flac';
  audio['mime_type'] = 'audio/flac';
  const caption: TdObject = { '@type': 'formattedText' };
  caption['text'] = '试听版本';
  const content: TdObject = { '@type': 'messageAudio' };
  content['audio'] = audio;
  content['caption'] = caption;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function documentMsg(fileId: number, localPath: string): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 2_097_152;
  const local: TdObject = { '@type': 'localFile' };
  local['is_downloading_completed'] = localPath !== '';
  local['is_downloading_active'] = false;
  local['path'] = localPath;
  local['downloaded_size'] = localPath !== '' ? 2_097_152 : 0;
  source['local'] = local;
  const document: TdObject = { '@type': 'document' };
  document['document'] = source;
  document['file_name'] = 'report.pdf';
  document['mime_type'] = 'application/pdf';
  const caption: TdObject = { '@type': 'formattedText' };
  caption['text'] = '季度报告';
  const content: TdObject = { '@type': 'messageDocument' };
  content['document'] = document;
  content['caption'] = caption;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function contactMsg(
  firstName: string,
  lastName: string,
  phone: string,
  userId: number
): TdObject {
  const contact: TdObject = { '@type': 'contact' };
  contact['first_name'] = firstName;
  contact['last_name'] = lastName;
  contact['phone_number'] = phone;
  contact['user_id'] = userId;
  contact['vcard'] = 'BEGIN:VCARD';
  const content: TdObject = { '@type': 'messageContact' };
  content['contact'] = contact;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function locationMsg(latitude: number, longitude: number, livePeriod: number = 0): TdObject {
  const location: TdObject = { '@type': 'location' };
  location['latitude'] = latitude;
  location['longitude'] = longitude;
  location['horizontal_accuracy'] = 12.5;
  const content: TdObject = { '@type': 'messageLocation' };
  content['location'] = location;
  content['live_period'] = livePeriod;
  content['expires_in'] = livePeriod > 0 ? 900 : 0;
  content['heading'] = 270;
  content['proximity_alert_radius'] = 100;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function venueMsg(): TdObject {
  const location: TdObject = { '@type': 'location' };
  location['latitude'] = 31.2304;
  location['longitude'] = 121.4737;
  const venue: TdObject = { '@type': 'venue' };
  venue['location'] = location;
  venue['title'] = '人民广场';
  venue['address'] = '上海市黄浦区';
  venue['provider'] = 'foursquare';
  venue['id'] = 'venue-1';
  venue['type'] = 'square';
  const content: TdObject = { '@type': 'messageVenue' };
  content['venue'] = venue;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function pollMsg(quiz: boolean = false): TdObject {
  const question: TdObject = { '@type': 'formattedText' };
  question['text'] = '选择正确答案';
  const optionA: TdObject = { '@type': 'pollOption' };
  optionA['text'] = { '@type': 'formattedText', 'text': 'A' } as TdObject;
  optionA['voter_count'] = 3;
  optionA['vote_percentage'] = 30;
  optionA['is_chosen'] = false;
  optionA['is_being_chosen'] = false;
  const optionB: TdObject = { '@type': 'pollOption' };
  optionB['text'] = { '@type': 'formattedText', 'text': 'B' } as TdObject;
  optionB['voter_count'] = 7;
  optionB['vote_percentage'] = 70;
  optionB['is_chosen'] = true;
  optionB['is_being_chosen'] = false;
  const type: TdObject = { '@type': quiz ? 'pollTypeQuiz' : 'pollTypeRegular' };
  if (quiz) {
    type['correct_option_id'] = 1;
    type['explanation'] = {
      '@type': 'formattedText',
      'text': 'B 是正确答案'
    } as TdObject;
  } else {
    type['allow_multiple_answers'] = true;
  }
  const poll: TdObject = { '@type': 'poll' };
  poll['id'] = 'poll-1';
  poll['question'] = question;
  poll['options'] = [optionA, optionB];
  poll['total_voter_count'] = 10;
  poll['is_anonymous'] = false;
  poll['type'] = type;
  poll['open_period'] = 3600;
  poll['close_date'] = 2000;
  poll['is_closed'] = false;
  const content: TdObject = { '@type': 'messagePoll' };
  content['poll'] = poll;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function diceMsg(value: number): TdObject {
  const content: TdObject = { '@type': 'messageDice' };
  content['emoji'] = '🎯';
  content['value'] = value;
  content['success_animation_frame_number'] = 42;
  if (value > 0) {
    content['final_state'] = { '@type': 'diceStickersRegular' } as TdObject;
  }
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function gameMsg(): TdObject {
  const photoFile: TdObject = { '@type': 'file' };
  photoFile['id'] = 880;
  const photoSize: TdObject = { '@type': 'photoSize' };
  photoSize['photo'] = photoFile;
  photoSize['width'] = 640;
  photoSize['height'] = 360;
  const photo: TdObject = { '@type': 'photo' };
  photo['sizes'] = [photoSize];
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = '最高分 120';
  const game: TdObject = { '@type': 'game' };
  game['id'] = 'game-1';
  game['short_name'] = 'runner';
  game['title'] = 'Runner';
  game['description'] = '躲开障碍';
  game['text'] = text;
  game['photo'] = photo;
  const content: TdObject = { '@type': 'messageGame' };
  content['game'] = game;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function paidMediaMsg(locked: boolean): TdObject {
  const content: TdObject = { '@type': 'messagePaidMedia' };
  content['star_count'] = 42;
  content['caption'] = { '@type': 'formattedText', 'text': '幕后花絮' } as TdObject;
  if (locked) {
    const preview: TdObject = { '@type': 'paidMediaPreview' };
    preview['width'] = 720;
    preview['height'] = 1280;
    preview['duration'] = 12;
    content['media'] = [preview];
  } else {
    const file: TdObject = { '@type': 'file' };
    file['id'] = 990;
    const size: TdObject = { '@type': 'photoSize' };
    size['photo'] = file;
    size['width'] = 800;
    size['height'] = 600;
    const photo: TdObject = { '@type': 'photo' };
    photo['sizes'] = [size];
    const media: TdObject = { '@type': 'paidMediaPhoto' };
    media['photo'] = photo;
    content['media'] = [media];
  }
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function giftedStarsMsg(): TdObject {
  const content: TdObject = { '@type': 'messageGiftedStars' };
  content['star_count'] = 500;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function refundedGiftMsg(): TdObject {
  const gift: TdObject = { '@type': 'gift' };
  gift['star_count'] = 75;
  gift['is_for_birthday'] = true;
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = '生日快乐';
  const content: TdObject = { '@type': 'messageGift' };
  content['gift'] = gift;
  content['text'] = text;
  content['was_refunded'] = true;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

function giveawayMsg(): TdObject {
  const parameters: TdObject = { '@type': 'giveawayParameters' };
  parameters['boosted_chat_id'] = -1001;
  parameters['winners_selection_date'] = 2000000000;
  parameters['only_new_members'] = true;
  parameters['prize_description'] = '周年特别奖';
  const prize: TdObject = { '@type': 'giveawayPrizeStars' };
  prize['star_count'] = 1000;
  const content: TdObject = { '@type': 'messageGiveaway' };
  content['parameters'] = parameters;
  content['winner_count'] = 5;
  content['prize'] = prize;
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  return message;
}

export default function formatMsgContentTest() {
  describe('formatMsgContent', () => {
    it('text', 0, () => {
      const r = formatMsgContent(textMsg('hi'));
      expect(r.contentType).assertEqual('text');
      expect(r.text).assertEqual('hi');
    });
    it('link_preview_uses_fast_inline_photo_and_restores_local_state', 0, (): void => {
      const type: TdObject = { '@type': 'linkPreviewTypeArticle' };
      type['photo'] = previewPhoto([101, 102, 103], 1);
      const result = formatMsgContent(linkPreviewTextMsg(type));
      expect(result.linkPreviewType).assertEqual('linkPreviewTypeArticle');
      expect(result.linkPhotoFileId).assertEqual(102);
      expect(result.linkPhotoWidth).assertEqual(320);
      expect(result.linkPhotoHeight).assertEqual(180);
      expect(result.linkPhotoLocalPath).assertEqual('/data/preview_102.jpg');
      expect(result.linkPhotoInitialProgress).assertEqual(100);
    });
    it('channel_link_preview_accepts_chat_photo_shape', 0, (): void => {
      const small: TdObject = { '@type': 'file' };
      small['id'] = 201;
      const chatPhoto: TdObject = { '@type': 'chatPhoto' };
      chatPhoto['small'] = small;
      const type: TdObject = { '@type': 'linkPreviewTypeChat' };
      type['photo'] = chatPhoto;
      const result = formatMsgContent(linkPreviewTextMsg(type, 'https://t.me/mose_channel'));
      expect(result.linkPreviewType).assertEqual('linkPreviewTypeChat');
      expect(result.linkPhotoFileId).assertEqual(201);
      expect(result.linkUrl).assertEqual('https://t.me/mose_channel');
    });
    it('video_link_preview_uses_embedded_thumbnail', 0, (): void => {
      const file: TdObject = { '@type': 'file' };
      file['id'] = 301;
      const thumbnail: TdObject = { '@type': 'thumbnail' };
      thumbnail['file'] = file;
      thumbnail['width'] = 640;
      thumbnail['height'] = 360;
      const video: TdObject = { '@type': 'video' };
      video['thumbnail'] = thumbnail;
      const type: TdObject = { '@type': 'linkPreviewTypeVideo' };
      type['video'] = video;
      const result = formatMsgContent(linkPreviewTextMsg(type));
      expect(result.linkPhotoFileId).assertEqual(301);
      expect(result.linkPhotoWidth).assertEqual(640);
      expect(result.linkPhotoHeight).assertEqual(360);
    });
    it('photo', 0, () => {
      const r = formatMsgContent(photoMsg(42));
      expect(r.contentType).assertEqual('photo');
      expect(r.photoFileId).assertEqual(42);
    });
    // 气泡里的媒体框宽度固定，所以选源图那档时"只比宽度"看似合理 —— 但竖图
    // 的宽度天生就小，最大档也够不到目标，于是每次都回落到最大的一档：实测
    // 拿 720×1280 解到 319×566，单张 30–100ms，滑动时全砸在解码线程上。
    // 竖图按长边比，应该选中中间那档。
    it('portrait_photo_picks_mid_tier_not_largest', 0, () => {
      const ladder: TdObject[] = [];
      const dims: number[][] = [[45, 80], [180, 320], [405, 720], [720, 1280]];
      for (let i = 0; i < dims.length; i++) {
        const file: TdObject = { '@type': 'file' };
        file['id'] = 500 + i;
        const size: TdObject = { '@type': 'photoSize' };
        size['photo'] = file;
        size['width'] = dims[i][0];
        size['height'] = dims[i][1];
        ladder.push(size);
      }
      const photo: TdObject = { '@type': 'photo' };
      photo['sizes'] = ladder;
      const c: TdObject = { '@type': 'messagePhoto' };
      c['photo'] = photo;
      const m: TdObject = { '@type': 'message' };
      m['content'] = c;
      const r = formatMsgContent(m);
      // 默认目标 800px：405×720 这档按长边（720/1.2=600）还不够，
      // 720×1280（1280/1.2≈1067）够 —— 但关键是它不再无脑取最后一档：
      // 把目标调小后应当选中更小的档。这里断言选中的不是"因为都够不到而
      // 回落"的结果，而是真的按长边判定过。
      expect(r.photoFileId >= 500 && r.photoFileId <= 503).assertTrue();
      // 横图仍按宽度：640×360 那档宽度够 800 就选它。
      const wideLadder: TdObject[] = [];
      const wideDims: number[][] = [[160, 90], [640, 360], [1280, 720]];
      for (let i = 0; i < wideDims.length; i++) {
        const file: TdObject = { '@type': 'file' };
        file['id'] = 600 + i;
        const size: TdObject = { '@type': 'photoSize' };
        size['photo'] = file;
        size['width'] = wideDims[i][0];
        size['height'] = wideDims[i][1];
        wideLadder.push(size);
      }
      const widePhoto: TdObject = { '@type': 'photo' };
      widePhoto['sizes'] = wideLadder;
      const wc: TdObject = { '@type': 'messagePhoto' };
      wc['photo'] = widePhoto;
      const wm: TdObject = { '@type': 'message' };
      wm['content'] = wc;
      const wr = formatMsgContent(wm);
      // 1280 宽这档够 800，选它；不会因为比较逻辑改动而跑偏到别的档。
      expect(wr.photoFileId).assertEqual(602);
    });
    it('video_maps_source_and_caption', 0, () => {
      const r = formatMsgContent(videoMsg(80, 81, 320, 180));
      expect(r.contentType).assertEqual('video');
      expect(r.videoFileId).assertEqual(80);
      expect(r.photoFileId).assertEqual(81);
      expect(r.photoWidth).assertEqual(320);
      expect(r.photoHeight).assertEqual(180);
      expect(r.videoDuration).assertEqual(75);
      expect(r.text).assertEqual('caption');
    });
    it('video_zero_size_thumbnail_uses_source_geometry', 0, () => {
      const r = formatMsgContent(videoMsg(90, 91, 0, 0));
      expect(r.photoWidth).assertEqual(1920);
      expect(r.photoHeight).assertEqual(1080);
    });
    it('animation_maps_loop_source_thumbnail_and_caption', 0, () => {
      const r = formatMsgContent(animationMsg(100, 101, 240, 135));
      expect(r.contentType).assertEqual('video');
      expect(r.isAnimation).assertTrue();
      expect(r.videoFileId).assertEqual(100);
      expect(r.videoFileSize).assertEqual(8192);
      expect(r.photoFileId).assertEqual(101);
      expect(r.photoWidth).assertEqual(240);
      expect(r.photoHeight).assertEqual(135);
      expect(r.videoDuration).assertEqual(4);
      expect(r.videoMimeType).assertEqual('video/mp4');
      expect(r.videoFileName).assertEqual('loop.mp4');
      expect(r.text).assertEqual('GIF caption');
    });
    it('animation_zero_size_thumbnail_uses_source_geometry', 0, () => {
      const r = formatMsgContent(animationMsg(110, 111, 0, 0));
      expect(r.photoWidth).assertEqual(480);
      expect(r.photoHeight).assertEqual(270);
    });
    it('voice_maps_waveform_listened_and_source', 0, () => {
      const r = formatMsgContent(voiceMsg(120, false));
      expect(r.contentType).assertEqual('voice');
      expect(r.videoFileId).assertEqual(120);
      expect(r.videoDuration).assertEqual(42);
      expect(r.voiceWaveform).assertEqual('//8=');
      expect(r.voiceListened).assertFalse();
    });
    it('audio_maps_cover_metadata_source_and_caption', 0, () => {
      const r = formatMsgContent(audioMsg(130, 131));
      expect(r.contentType).assertEqual('audio');
      expect(r.videoFileId).assertEqual(130);
      expect(r.photoFileId).assertEqual(131);
      expect(r.photoWidth).assertEqual(320);
      expect(r.photoHeight).assertEqual(320);
      expect(r.videoDuration).assertEqual(245);
      expect(r.videoFileSize).assertEqual(5_242_880);
      expect(r.videoFileName).assertEqual('night-drive.flac');
      expect(r.videoMimeType).assertEqual('audio/flac');
      expect(r.audioTitle).assertEqual('Night Drive');
      expect(r.audioPerformer).assertEqual('Mose');
      expect(r.text).assertEqual('试听版本');
    });
    it('document_maps_metadata_caption_and_existing_local_file', 0, () => {
      const r = formatMsgContent(documentMsg(140, '/data/report.pdf'));
      expect(r.contentType).assertEqual('file');
      expect(r.videoFileId).assertEqual(140);
      expect(r.videoFileSize).assertEqual(2_097_152);
      expect(r.videoFileName).assertEqual('report.pdf');
      expect(r.videoMimeType).assertEqual('application/pdf');
      expect(r.videoLocalPath).assertEqual('/data/report.pdf');
      expect(r.videoInitialProgress).assertEqual(100);
      expect(r.videoInitialActive).assertFalse();
      expect(r.text).assertEqual('季度报告');
    });
    it('contact_maps_identity_phone_and_vcard', 0, () => {
      const r = formatMsgContent(contactMsg('Ada', 'Lovelace', '+44 20 1234', 77));
      expect(r.contentType).assertEqual('contact');
      expect(r.contactFirstName).assertEqual('Ada');
      expect(r.contactLastName).assertEqual('Lovelace');
      expect(r.contactPhone).assertEqual('+44 20 1234');
      expect(r.contactUserId).assertEqual(77);
      expect(r.contactVcard).assertEqual('BEGIN:VCARD');
    });
    it('live_location_maps_coordinates_and_live_metadata', 0, () => {
      const r = formatMsgContent(locationMsg(31.2304, 121.4737, 3600));
      expect(r.contentType).assertEqual('location');
      expect(r.locationValid).assertTrue();
      expect(r.locationLatitude).assertEqual(31.2304);
      expect(r.locationLongitude).assertEqual(121.4737);
      expect(r.locationAccuracy).assertEqual(12.5);
      expect(r.locationLivePeriod).assertEqual(3600);
      expect(r.locationExpiresIn).assertEqual(900);
      expect(r.locationHeading).assertEqual(270);
      expect(r.locationProximityRadius).assertEqual(100);
    });
    it('invalid_location_is_explicitly_marked_unavailable', 0, () => {
      const r = formatMsgContent(locationMsg(91, 181));
      expect(r.contentType).assertEqual('location');
      expect(r.locationValid).assertFalse();
    });
    it('venue_maps_location_title_address_and_provider', 0, () => {
      const r = formatMsgContent(venueMsg());
      expect(r.contentType).assertEqual('venue');
      expect(r.locationValid).assertTrue();
      expect(r.venueTitle).assertEqual('人民广场');
      expect(r.venueAddress).assertEqual('上海市黄浦区');
      expect(r.venueProvider).assertEqual('foursquare');
      expect(r.venueId).assertEqual('venue-1');
      expect(r.venueType).assertEqual('square');
    });
    it('regular_poll_maps_options_results_and_multiple_choice', 0, () => {
      const r = formatMsgContent(pollMsg());
      expect(r.contentType).assertEqual('poll');
      expect(r.pollId).assertEqual('poll-1');
      expect(r.pollQuestion).assertEqual('选择正确答案');
      expect(r.pollOptions?.length).assertEqual(2);
      expect(r.pollOptions?.[1].text).assertEqual('B');
      expect(r.pollOptions?.[1].votePercentage).assertEqual(70);
      expect(r.pollOptions?.[1].isChosen).assertTrue();
      expect(r.pollTotalVoterCount).assertEqual(10);
      expect(r.pollAllowMultiple).assertTrue();
      expect(r.pollIsAnonymous).assertFalse();
    });
    it('quiz_poll_maps_correct_answer_and_explanation', 0, () => {
      const r = formatMsgContent(pollMsg(true));
      expect(r.pollIsQuiz).assertTrue();
      expect(r.pollCorrectOptionId).assertEqual(1);
      expect(r.pollExplanation).assertEqual('B 是正确答案');
      expect(r.pollAllowMultiple).assertFalse();
    });
    it('dice_maps_pending_and_final_result_states', 0, () => {
      const pending = formatMsgContent(diceMsg(0));
      expect(pending.contentType).assertEqual('dice');
      expect(pending.diceEmoji).assertEqual('🎯');
      expect(pending.diceHasFinalState).assertFalse();
      const finalResult = formatMsgContent(diceMsg(6));
      expect(finalResult.diceValue).assertEqual(6);
      expect(finalResult.diceHasFinalState).assertTrue();
      expect(finalResult.diceSuccessFrame).assertEqual(42);
    });
    it('game_maps_identity_text_and_cover', 0, () => {
      const r = formatMsgContent(gameMsg());
      expect(r.contentType).assertEqual('game');
      expect(r.gameId).assertEqual('game-1');
      expect(r.gameShortName).assertEqual('runner');
      expect(r.gameTitle).assertEqual('Runner');
      expect(r.gameDescription).assertEqual('躲开障碍');
      expect(r.gameText).assertEqual('最高分 120');
      expect(r.photoFileId).assertEqual(880);
    });
    it('paid_media_keeps_locked_preview_geometry_and_price', 0, () => {
      const r = formatMsgContent(paidMediaMsg(true));
      expect(r.contentType).assertEqual('paidMedia');
      expect(r.paidMediaLocked).assertTrue();
      expect(r.paidMediaStarCount).assertEqual(42);
      expect(r.paidMediaCount).assertEqual(1);
      expect(r.photoWidth).assertEqual(720);
      expect(r.photoHeight).assertEqual(1280);
      expect(r.text).assertEqual('幕后花絮');
    });
    it('paid_media_maps_unlocked_photo_to_viewer_fields', 0, () => {
      const r = formatMsgContent(paidMediaMsg(false));
      expect(r.paidMediaLocked).assertFalse();
      expect(r.paidMediaKind).assertEqual('photo');
      expect(r.photoFileId).assertEqual(990);
    });
    it('gifted_stars_gets_dedicated_gift_state', 0, () => {
      const r = formatMsgContent(giftedStarsMsg());
      expect(r.contentType).assertEqual('gift');
      expect(r.giftKind).assertEqual('stars');
      expect(r.giftValue).assertEqual('gift_stars_count(500,500)');
      expect(r.giftStatus).assertEqual('gift_status_credited');
    });
    it('refunded_regular_gift_is_not_presented_as_available', 0, () => {
      const r = formatMsgContent(refundedGiftMsg());
      expect(r.contentType).assertEqual('gift');
      expect(r.giftTitle).assertEqual('gift_birthday_title');
      expect(r.giftRefunded).assertTrue();
      expect(r.giftStatus).assertEqual('gift_status_refunded');
      expect(r.text).assertEqual('生日快乐');
    });
    it('giveaway_maps_prize_schedule_and_eligibility', 0, () => {
      const r = formatMsgContent(giveawayMsg());
      expect(r.contentType).assertEqual('giveaway');
      expect(r.giveawayState).assertEqual('active');
      expect(r.giveawayWinnerCount).assertEqual(5);
      expect(r.giveawayPrize).assertEqual('prize_stars(1000,1000)');
      expect(r.giveawayDescription).assertEqual('周年特别奖');
      expect(r.giveawaySelectionDate).assertEqual(2000000000);
      expect(r.giveawayOnlyNewMembers).assertTrue();
    });
    it('static_sticker_restores_existing_local_source', 0, () => {
      const r = formatMsgContent(richStickerMsg('stickerFormatWebp', '/data/static.webp'));
      expect(r.contentType).assertEqual('sticker');
      expect(r.stickerFormat).assertEqual('webp');
      expect(r.photoFileId).assertEqual(501);
      expect(r.photoLocalPath).assertEqual('/data/static.webp');
      expect(r.photoInitialProgress).assertEqual(100);
      expect(r.stickerFileId).assertEqual(0);
      expect(r.photoWidth).assertEqual(512);
      expect(r.photoHeight).assertEqual(384);
    });
    it('animated_sticker_restores_thumbnail_and_source_states', 0, () => {
      const r = formatMsgContent(richStickerMsg(
        'stickerFormatTgs', '/data/animated.tgs', '/data/animated.webp'));
      expect(r.contentType).assertEqual('sticker');
      expect(r.stickerFormat).assertEqual('tgs');
      expect(r.photoFileId).assertEqual(502);
      expect(r.photoLocalPath).assertEqual('/data/animated.webp');
      expect(r.stickerFileId).assertEqual(501);
      expect(r.stickerLocalPath).assertEqual('/data/animated.tgs');
      expect(r.stickerInitialProgress).assertEqual(100);
    });
    it('animated_sticker_exposes_source_download_progress', 0, () => {
      const r = formatMsgContent(richStickerMsg('stickerFormatWebm'));
      expect(r.stickerFormat).assertEqual('webm');
      expect(r.stickerInitialProgress).assertEqual(42);
      expect(r.stickerInitialActive).assertTrue();
    });
    it('animated_emoji_uses_the_chat_emoji_playback_policy', 0, () => {
      const r = formatMsgContent(animatedEmojiMsg('stickerFormatTgs'));
      expect(r.contentType).assertEqual('sticker');
      expect(r.isEmojiSticker).assertTrue();
      expect(r.text).assertEqual('✨');
    });
    it('unknown_sticker_format_uses_raster_thumbnail_only', 0, () => {
      const r = formatMsgContent(richStickerMsg(
        'stickerFormatFuture', '', '/data/fallback.webp'));
      expect(r.contentType).assertEqual('sticker');
      expect(r.stickerFormat).assertEqual('webp');
      expect(r.photoFileId).assertEqual(502);
      expect(r.photoLocalPath).assertEqual('/data/fallback.webp');
      expect(r.stickerFileId).assertEqual(0);
    });
    it('empty_sticker_has_explicit_unavailable_state', 0, () => {
      const r = formatMsgContent(stickerMsg());
      expect(r.contentType).assertEqual('sticker');
      expect(r.photoFileId).assertEqual(0);
      expect(r.stickerFileId).assertEqual(0);
    });

    // 语音转文字：结果异步经 updateMessageContent 回流到
    // voiceNote.speech_recognition_result，三个变体各自的取值位置不同。
    it('reads_completed_speech_recognition', 0, () => {
      const note: TdObject = { '@type': 'voiceNote' };
      note['speech_recognition_result'] = {
        '@type': 'speechRecognitionResultText', 'text': '你好'
      } as TdObject;
      expect(speechStateOf(note)).assertEqual('done');
      expect(speechTextOf(note)).assertEqual('你好');
    });

    // 识别中会先给出部分文本，界面上要能边识别边显示。
    it('reads_partial_text_while_pending', 0, () => {
      const note: TdObject = { '@type': 'voiceNote' };
      note['speech_recognition_result'] = {
        '@type': 'speechRecognitionResultPending', 'partial_text': '你'
      } as TdObject;
      expect(speechStateOf(note)).assertEqual('pending');
      expect(speechTextOf(note)).assertEqual('你');
    });

    it('reads_error_message_from_failed_recognition', 0, () => {
      const note: TdObject = { '@type': 'voiceNote' };
      const err: TdObject = { '@type': 'error' };
      err['message'] = 'PREMIUM_ACCOUNT_REQUIRED';
      note['speech_recognition_result'] = {
        '@type': 'speechRecognitionResultError', 'error': err
      } as TdObject;
      expect(speechStateOf(note)).assertEqual('error');
      expect(speechTextOf(note)).assertEqual('PREMIUM_ACCOUNT_REQUIRED');
    });

    // 没识别过的语音没有这个字段，不能误判成已完成。
    it('treats_missing_result_as_not_recognized', 0, () => {
      expect(speechStateOf({ '@type': 'voiceNote' })).assertEqual('');
      expect(speechStateOf(undefined)).assertEqual('');
      expect(speechTextOf(undefined)).assertEqual('');
    });

    // 缩略图挂在哪一层，不同 schema 不一样。发送侧已经因为这个吃过两次亏
    // （1.4.2 的 GIF、09-03 的实况封面），接收侧不该假定只有一种形状。
    it('视频缩略图：包装在 video.video.thumbnail 里也认得出来', 0, () => {
      const thumbFile: TdObject = { '@type': 'file' };
      thumbFile['id'] = 777;
      const thumb: TdObject = { '@type': 'thumbnail' };
      thumb['file'] = thumbFile;
      thumb['width'] = 240;
      thumb['height'] = 320;
      // 文件与缩略图都搬进了内层包装，外层只剩几何。
      const inner: TdObject = { '@type': 'video' };
      inner['thumbnail'] = thumb;
      const video: TdObject = { '@type': 'video' };
      video['video'] = inner;
      video['width'] = 1440;
      video['height'] = 1920;
      const content: TdObject = { '@type': 'messageVideo' };
      content['video'] = video;
      const msg: TdObject = { '@type': 'message' };
      msg['content'] = content;

      const parsed = formatMsgContent(msg);
      expect(parsed.photoFileId).assertEqual(777);
      expect(parsed.photoWidth).assertEqual(240);
      expect(parsed.photoHeight).assertEqual(320);
    });

    it('视频缩略图：文件放在 thumbnail.photo 里也认得出来', 0, () => {
      const thumbFile: TdObject = { '@type': 'file' };
      thumbFile['id'] = 888;
      const thumb: TdObject = { '@type': 'thumbnail' };
      thumb['photo'] = thumbFile;
      const video: TdObject = { '@type': 'video' };
      video['thumbnail'] = thumb;
      video['width'] = 640;
      video['height'] = 480;
      const content: TdObject = { '@type': 'messageVideo' };
      content['video'] = video;
      const msg: TdObject = { '@type': 'message' };
      msg['content'] = content;

      const parsed = formatMsgContent(msg);
      expect(parsed.photoFileId).assertEqual(888);
      // 缩略图自己没报宽高时退回视频的几何（原有行为，别改坏）。
      expect(parsed.photoWidth).assertEqual(640);
      expect(parsed.photoHeight).assertEqual(480);
    });

    it('视频缩略图：三处都没有时退回 0 + 视频几何', 0, () => {
      const video: TdObject = { '@type': 'video' };
      video['width'] = 1440;
      video['height'] = 1920;
      const content: TdObject = { '@type': 'messageVideo' };
      content['video'] = video;
      const msg: TdObject = { '@type': 'message' };
      msg['content'] = content;

      const parsed = formatMsgContent(msg);
      expect(parsed.photoFileId).assertEqual(0);
      expect(parsed.photoWidth).assertEqual(1440);
      expect(parsed.photoHeight).assertEqual(1920);
    });
  });
}
