import { fileOpenMimeType } from './fileMessage';

export interface FilePreviewSource {
  fileId: number;
  filePath: string;
  fileSize: number;
  thumbnailId: number;
  thumbnailPath: string;
  mini: string;
  kind: string;
}
export function filePreviewKind(name: string, mime: string): string {
  const type = fileOpenMimeType(name, mime);
  return type.startsWith('image/') ? 'image' : type.startsWith('video/') ? 'video' : '';
}
export function fileHasPreview(source: FilePreviewSource): boolean {
  return source.thumbnailId > 0 || source.thumbnailPath !== '' || source.mini !== '' ||
    (source.filePath !== '' && source.kind !== '');
}
export function sameFilePreview(a: FilePreviewSource | null, b: FilePreviewSource): boolean {
  return a !== null && a.fileId === b.fileId && a.filePath === b.filePath && a.fileSize === b.fileSize &&
    a.thumbnailId === b.thumbnailId && a.thumbnailPath === b.thumbnailPath && a.mini === b.mini && a.kind === b.kind;
}
