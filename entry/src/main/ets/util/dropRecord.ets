import { SharedRecordLike } from './sharedContent';

export interface DropRecordFields {
  textContent?: string;
  plainContent?: string;
  url?: string;
  uri?: string;
  imageUri?: string;
  videoUri?: string;
  audioUri?: string;
  oriUri?: string;
  fileType?: string;
}

// UDMF legacy subclasses and modern entry objects use different URI field names.
export function normalizeDropRecord(type: string, parent: string, value: DropRecordFields): SharedRecordLike {
  if (type === 'general.file-uri') {
    return { utd: value.fileType || 'general.file', uri: value.oriUri || value.uri || '' };
  }
  if (type === 'general.plain-text') { return { utd: type, content: value.textContent ?? '' }; }
  if (type === 'general.hyperlink') { return { utd: type, content: value.url ?? '' }; }
  if (type === 'general.html') { return { utd: type, content: value.plainContent ?? '' }; }
  let uri = value.uri ?? '';
  if (parent === 'general.image') { uri = value.imageUri || uri; }
  else if (parent === 'general.video') { uri = value.videoUri || uri; }
  else if (parent === 'general.audio') { uri = value.audioUri || uri; }
  else if (parent !== 'general.file') { throw new Error('unsupported drop type'); }
  return { utd: type, uri: uri };
}
