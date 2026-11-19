import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { TdObject } from '../../tdkit/TdTypes';
import { watchGiveawayPeer, GiveawayPeerInfo } from '../../services/GiveawayPeerCache';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { documentFileId, documentFilePath } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { DrawnGiveawayAudienceLayout, DrawnGiveawayPeerSlot } from './DrawnGiveawayAudienceLayout';

class DrawnGiveawayPeerImage {
  private model: DrawnGiveawayAudienceLayout;
  private slot: DrawnGiveawayPeerSlot;
  private index: number;
  private owner: string;
  private offPeer: (() => void) | null = null;
  private offFile: (() => void) | null = null;
  private fileId: number = 0;
  private path: string = '';
  private active: boolean = true;
  private generation: number = 0;
  private session: CachedImageSession;
  constructor(model: DrawnGiveawayAudienceLayout, index: number, owner: string) {
    this.model = model; this.slot = model.slots[index]; this.index = index; this.owner = owner;
    this.session = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean, width?: number, height?: number): void => {
      if (!this.active) { return; }
      this.slot.receiver.setPixels(pixels, width, height); this.model.invalidate();
    });
  }
  bind(ui: UIContext): void {
    this.slot.receiver.bind(ui, 24, 24, ImageFit.Cover, true, this.model.density);
    this.offPeer = watchGiveawayPeer(this.slot.id, this.slot.user, (info: GiveawayPeerInfo | null): void => {
      if (!this.active || info === null) { return; }
      this.model.queueName(this.index, info.name); this.photo(info.photo);
    });
  }
  private spec(): CachedImageSpec {
    return { path: this.path, boxWidth: 24, boxHeight: 24, fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `${this.owner}:${this.slot.key}:${this.fileId}` };
  }
  private photo(file: TdObject | undefined): void {
    const id = documentFileId(file), changed = id !== this.fileId;
    if (changed || file === undefined) {
      this.generation++; this.offFile?.(); this.offFile = null; this.slot.receiver.setPixels(undefined);
      this.session.dispose(); this.path = ''; this.fileId = id; this.model.invalidate();
    }
    if (file === undefined || id <= 0) { return; }
    const state = documentFileState(file);
    this.path = documentFilePath(file) || state.path || this.path;
    if (changed) {
      const token = this.generation;
      this.offFile = watchDocumentFile(file, (next: DocumentFileState): void => {
        if (!this.active || token !== this.generation) { return; }
        if (next.path !== '' || this.path === '') { this.path = next.path; }
        this.session.update(this.spec());
      });
      this.session.activate(this.spec()); requestDocumentFile(file, THUMBNAIL_PRIORITY);
    } else { this.session.update(this.spec()); }
  }
  dispose(): void {
    this.active = false; this.generation++; this.offPeer?.(); this.offPeer = null;
    this.offFile?.(); this.offFile = null; this.slot.receiver.setPixels(undefined); this.session.dispose();
  }
}

// No native component per peer. A physical attachment owns its subscriptions;
// late metadata/file/decode callbacks cannot publish into a reused attachment.
export class DrawnGiveawayAudienceController {
  private model: DrawnGiveawayAudienceLayout | null = null;
  private owner: string = '';
  private peers: DrawnGiveawayPeerImage[] = [];
  bind(ui: UIContext, model: DrawnGiveawayAudienceLayout, owner: string): void {
    if (this.model === model && this.owner === owner) { return; }
    this.dispose(); this.model = model; this.owner = owner;
    for (let i = 0; i < model.slots.length; i++) {
      const peer = new DrawnGiveawayPeerImage(model, i, owner); this.peers.push(peer); peer.bind(ui);
    }
  }
  dispose(): void {
    for (const peer of this.peers) { peer.dispose(); }
    this.peers.length = 0; this.model?.cancelPending(); this.model = null; this.owner = '';
  }
}
