import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { LegacyAlbumMessageBubble } from './LegacyAlbumMessageBubble';
import { DrawnMessageRow } from './DrawnMessageRow';
import { drawnAlbumEligible } from '../../util/drawnAlbumPolicy';
import { chatEnv } from '../../util/chatEnvMirror';
import { a11yRuntimeState } from '../../util/a11yState';

// Dispatch only. Unsupported cases retain their existing behavior and sharing
// the image/cache services does not opt other message types into the new shell.
@ComponentV2
export struct AlbumMessageBubble {
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private env = chatEnv;
  private a11y = a11yRuntimeState;

  build() {
    if (this.env.drawnEnabled !== false && this.env.drawnAlbum !== false && drawnAlbumEligible(this.group, this.data, this.env.bubbleMaterialOn, this.a11y.active)) {
      DrawnMessageRow({ group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    } else {
      LegacyAlbumMessageBubble({ group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    }
  }
}
