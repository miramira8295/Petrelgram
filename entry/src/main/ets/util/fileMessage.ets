import { str } from './strings';
import { formatFileSize } from './formatFileSize';

export interface FileTypeVisual {
  label: string;
  color: string;
}

const DOCUMENT_EXTENSIONS: string[] = ['doc', 'docx', 'odt', 'rtf', 'pages'];
const SHEET_EXTENSIONS: string[] = ['xls', 'xlsx', 'ods', 'csv', 'numbers'];
const SLIDE_EXTENSIONS: string[] = ['ppt', 'pptx', 'odp', 'key'];
const ARCHIVE_EXTENSIONS: string[] =
  ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'zst'];
const CODE_EXTENSIONS: string[] =
  ['js', 'ts', 'ets', 'json', 'xml', 'yaml', 'yml', 'html', 'css', 'java',
    'kt', 'swift', 'py', 'go', 'rs', 'c', 'cc', 'cpp', 'h', 'hpp', 'sh'];
const TEXT_EXTENSIONS: string[] = ['txt', 'md', 'log', 'ini', 'conf'];
const IMAGE_EXTENSIONS: string[] =
  ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'avif'];
const VIDEO_EXTENSIONS: string[] = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'flv', 'm4v'];
const AUDIO_EXTENSIONS: string[] = ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'];
const APP_EXTENSIONS: string[] = ['hap', 'apk', 'ipa', 'app'];

function mimeExtension(mimeType: string): string {
  const mime: string = mimeType.trim().toLowerCase();
  if (mime === 'application/pdf') {
    return 'pdf';
  }
  if (mime.indexOf('word') >= 0 || mime.indexOf('opendocument.text') >= 0) {
    return 'doc';
  }
  if (mime.indexOf('sheet') >= 0 || mime.indexOf('excel') >= 0 ||
    mime.indexOf('opendocument.spreadsheet') >= 0) {
    return 'xls';
  }
  if (mime.indexOf('presentation') >= 0 || mime.indexOf('powerpoint') >= 0) {
    return 'ppt';
  }
  if (mime.indexOf('zip') >= 0 || mime.indexOf('compressed') >= 0 ||
    mime.indexOf('archive') >= 0) {
    return 'zip';
  }
  if (mime.startsWith('image/')) {
    return 'image';
  }
  if (mime.startsWith('video/')) {
    return 'video';
  }
  if (mime.startsWith('audio/')) {
    return 'audio';
  }
  if (mime.startsWith('text/')) {
    return 'txt';
  }
  return '';
}

export function fileExtension(fileName: string, mimeType: string): string {
  const name: string = fileName.trim();
  const dot: number = name.lastIndexOf('.');
  if (dot >= 0 && dot + 1 < name.length) {
    const extension: string = name.substring(dot + 1).trim().toLowerCase();
    if (extension.length > 0 && extension.length <= 10 &&
      extension.indexOf('/') < 0 && extension.indexOf('\\') < 0) {
      return extension;
    }
  }
  return mimeExtension(mimeType);
}

export function fileTypeVisual(fileName: string, mimeType: string): FileTypeVisual {
  const extension: string = fileExtension(fileName, mimeType);
  if (extension === 'pdf') {
    return { label: 'PDF', color: '#E65A5A' };
  }
  if (DOCUMENT_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'DOC', color: '#4B83D8' };
  }
  if (SHEET_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'XLS', color: '#43A06B' };
  }
  if (SLIDE_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'PPT', color: '#E07A45' };
  }
  if (ARCHIVE_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'ZIP', color: '#8A6CC7' };
  }
  if (CODE_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'CODE', color: '#536477' };
  }
  if (TEXT_EXTENSIONS.indexOf(extension) >= 0 || extension === 'txt') {
    return { label: 'TXT', color: '#5B8FA8' };
  }
  if (IMAGE_EXTENSIONS.indexOf(extension) >= 0 || extension === 'image') {
    return { label: 'IMG', color: '#B45F9B' };
  }
  if (VIDEO_EXTENSIONS.indexOf(extension) >= 0 || extension === 'video') {
    return { label: 'VIDEO', color: '#765CC6' };
  }
  if (AUDIO_EXTENSIONS.indexOf(extension) >= 0 || extension === 'audio') {
    return { label: 'AUDIO', color: '#4F91C8' };
  }
  if (APP_EXTENSIONS.indexOf(extension) >= 0) {
    return { label: 'APP', color: '#D26767' };
  }
  if (extension !== '' && extension.length <= 4) {
    return { label: extension.toUpperCase(), color: '#778899' };
  }
  return { label: 'FILE', color: '#778899' };
}

export function fileOpenMimeType(fileName: string, mimeType: string): string {
  const supplied: string = mimeType.trim().toLowerCase();
  if (supplied !== '' && supplied !== 'application/octet-stream') {
    return supplied;
  }
  const extension: string = fileExtension(fileName, '');
  if (extension === 'pdf') {
    return 'application/pdf';
  }
  if (DOCUMENT_EXTENSIONS.indexOf(extension) >= 0) {
    return extension === 'doc'
      ? 'application/msword'
      : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (SHEET_EXTENSIONS.indexOf(extension) >= 0) {
    return extension === 'xls'
      ? 'application/vnd.ms-excel'
      : (extension === 'csv' ? 'text/csv'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  if (SLIDE_EXTENSIONS.indexOf(extension) >= 0) {
    return extension === 'ppt'
      ? 'application/vnd.ms-powerpoint'
      : 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }
  if (ARCHIVE_EXTENSIONS.indexOf(extension) >= 0) {
    return extension === 'zip' ? 'application/zip' : 'application/octet-stream';
  }
  if (IMAGE_EXTENSIONS.indexOf(extension) >= 0) {
    return `image/${extension === 'jpg' ? 'jpeg' : extension}`;
  }
  if (VIDEO_EXTENSIONS.indexOf(extension) >= 0) {
    return `video/${extension === 'mov' ? 'quicktime' : extension}`;
  }
  if (AUDIO_EXTENSIONS.indexOf(extension) >= 0) {
    return `audio/${extension === 'mp3' ? 'mpeg' : extension}`;
  }
  if (TEXT_EXTENSIONS.indexOf(extension) >= 0 || CODE_EXTENSIONS.indexOf(extension) >= 0) {
    return 'text/plain';
  }
  return supplied;
}

export function displayFileName(fileName: string): string {
  const name: string = fileName.trim();
  return name !== '' ? name : str('file_unnamed');
}

export function fileStatusText(
  fileId: number,
  filePath: string,
  fileSize: number,
  downloadActive: boolean,
  downloadProgress: number,
  downloadFailed: boolean,
  // 出站文件（issue #201 第 6 条）：本地路径从一开始就在，靠这个标志区分
  // "发送中"和"发完"；百分比复用 downloadProgress（通道里此时是上传进度）。
  uploading: boolean = false
): string {
  const size: string = formatFileSize(fileSize);
  const sizeLabel: string = size !== '' ? size : str('file_unknown_size');
  if (uploading) {
    return downloadProgress > 0
      ? str('file_uploading_pct', sizeLabel, downloadProgress)
      : str('file_uploading', sizeLabel);
  }
  if (filePath !== '') {
    return str('file_tap_open', sizeLabel);
  }
  if (fileId === 0) {
    return str('file_unavailable');
  }
  if (downloadFailed) {
    return str('file_download_failed');
  }
  if (downloadActive) {
    return downloadProgress > 0
      ? str('file_downloading_pct', sizeLabel, downloadProgress)
      : str('file_downloading', sizeLabel);
  }
  return str('file_tap_download', sizeLabel);
}
