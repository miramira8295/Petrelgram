import { MessageEntry } from '../store/MessageEntry';
import { VideoVariant } from './videoVariants';
import { EntryVideoFileRef, entryInlineFile } from './entryVideoVariant';

// MessageEntry replaces variant arrays on content changes. Cache just this
// mounted video's last input; no global retention or serialization of arrays.
export class DrawnSingleInlineFile {
  private variants: VideoVariant[] | null = null;
  private key: string = '';
  private value: EntryVideoFileRef | null = null;
  prepare(msg: MessageEntry): EntryVideoFileRef {
    const key = `${msg.videoFileId}:${msg.videoFileSize}:${msg.photoWidth}:${msg.photoHeight}:${msg.videoPath !== ''}`;
    if (this.value !== null && this.key === key && this.variants === msg.videoVariants) { return this.value; }
    this.value = entryInlineFile(msg) ?? { fileId: msg.videoFileId, fileSize: msg.videoFileSize, local: false };
    this.key = key; this.variants = msg.videoVariants; return this.value;
  }
}
