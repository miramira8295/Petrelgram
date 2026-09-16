import { TdObject } from '../tdkit/TdTypes';
import { MessageEntry, cloneMessage } from '../store/MessageEntry';
import {
  DC_KIND_PHOTO, DC_KIND_VIDEO, DC_STATE_COMPLETE, DC_TAB_ALL, DownloadCenterItem, DownloadCenterSection,
  downloadCenterItemId, filterDownloadCenterItems, groupDownloadCenterItems, progressPercent
} from './downloadCenterModel';

// 下载中心接聊天详情的媒体查看器（MediaViewerOverlay）：把当前页签里能看的图片 / 视频拼成一个临时相册喂给它。
// 查看器的左右滑本来就只在「同一相册的成员」之间滑（siblingIds = group.memberIds），翻页逻辑一行不用改。
// 2026-09-15 用户：图片页签里滑图片、视频页签里滑视频、「全部」里图片视频混着滑；没下完的视频也能滑到，边下边播。
//
// 成员 id 用 1…N 的临时编号，不用真实 message id：下载中心的条目来自不同会话，message id 只在会话内唯一。

export const DC_VIEWER_ALBUM_ID: string = 'dc_viewer';

export interface DownloadViewerSet {
  items: DownloadCenterItem[];
  startIndex: number;
}

export function viewerKindsForTab(tab: string): string[] {
  if (tab === DC_TAB_ALL) {
    return [DC_KIND_PHOTO, DC_KIND_VIDEO];
  }
  if (tab === DC_KIND_PHOTO || tab === DC_KIND_VIDEO) {
    return [tab];
  }
  return [];
}

// 图片要下完（查看器画的是本地原图）。
//
// 视频：**本地文件在**，或者有 fileId 可以流式——两者有其一就能播。
//
// 【改过一次，2026-09-16】原来只认 `fileId !== 0`，理由写的是「播放器按 fileId 挂」。
// 那是错的：两个引擎的取源顺序都是 localPath 优先（AvVideoPlayer 直接 openSync 本地
// 文件；StreamingVideoPlayer 的 sourceUrl = localPath），只有「没路径又没 fileId」才
// 真的放弃。而磁盘扫描出来的条目 fileId 恒为 0（TDLib 没有「路径 → fileId」的接口），
// 于是所有扫出来的视频都被甩给系统播放器——用户报「视频现在不会进入媒体查看器，
// 会使用系统工具播放」。
export function viewableInViewer(it: DownloadCenterItem): boolean {
  if (it.kind === DC_KIND_PHOTO) {
    return it.state === DC_STATE_COMPLETE && it.path !== '';
  }
  if (it.kind === DC_KIND_VIDEO) {
    return (it.state === DC_STATE_COMPLETE && it.path !== '') || it.fileId !== 0;
  }
  return false;
}

// 顺序与列表上看到的一致：同一套筛选（页签 + 搜索）、同一套分组排序（进行中在前、已完成在后）。
export function buildDownloadViewerSet(items: DownloadCenterItem[], tapped: DownloadCenterItem, tab: string,
  query: string, sort: string): DownloadViewerSet | null {
  const kinds: string[] = viewerKindsForTab(tab);
  if (kinds.indexOf(tapped.kind) < 0 || !viewableInViewer(tapped)) {
    return null;
  }
  const sections: DownloadCenterSection[] = groupDownloadCenterItems(filterDownloadCenterItems(items, tab, query), sort);
  const ordered: DownloadCenterItem[] = [];
  for (const section of sections) {
    for (const it of section.items) {
      if (kinds.indexOf(it.kind) >= 0 && viewableInViewer(it)) {
        ordered.push(it);
      }
    }
  }
  const id: string = downloadCenterItemId(tapped);
  const startIndex: number = ordered.findIndex((it: DownloadCenterItem): boolean => downloadCenterItemId(it) === id);
  if (startIndex < 0) {
    return null;
  }
  return { items: ordered, startIndex: startIndex };
}

export function viewerMessageIdAt(index: number): number {
  return index + 1;
}

export function viewerIndexOf(messageId: number): number {
  return messageId - 1;
}

// 造底板用的空消息：MessageEntry 字段很多，先按一条空文本消息解析出全套默认值，再覆盖媒体字段。
export function viewerBaseMessage(): TdObject {
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = '';
  text['entities'] = [];
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = text;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 0;
  const raw: TdObject = { '@type': 'message' };
  raw['id'] = 0;
  raw['date'] = 0;
  raw['sender_id'] = sender;
  raw['content'] = content;
  return raw;
}

export function viewerEntryFor(base: MessageEntry, it: DownloadCenterItem, messageId: number): MessageEntry {
  const e: MessageEntry = cloneMessage(base);
  e.id = messageId;
  e.rowId = messageId;
  e.albumId = DC_VIEWER_ALBUM_ID;
  e.date = Math.floor(it.mtime / 1000);
  e.text = '';
  // 查看器顶栏标题：视频用文件名，图片用发送者名——这里借来显示来源会话。
  e.senderName = it.session;
  const complete: boolean = it.state === DC_STATE_COMPLETE && it.path !== '';
  if (it.kind === DC_KIND_VIDEO) {
    e.contentType = 'video';
    e.videoFileId = it.fileId;
    e.videoPath = complete ? it.path : '';
    e.videoFileSize = it.size;
    e.videoMimeType = it.mimeType;
    e.videoFileName = it.name;
    e.videoProgress = progressPercent(it.downloaded, it.size, complete);
    e.videoFailed = false;
    return e;
  }
  e.contentType = 'photo';
  e.photoFileId = it.fileId;
  e.photoPath = it.path;
  e.photoProgress = 100;
  e.photoFullFileId = it.fileId;
  e.photoFullPath = it.path;
  e.photoFullProgress = 100;
  e.photoFullFailed = false;
  return e;
}
