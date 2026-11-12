import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { LegacyTextRow } from './LegacyTextRow';
import { DrawnMessageRow } from './DrawnMessageRow';
import { drawnTextRowEligible } from '../../util/drawnTextRowPolicy';
import { chatEnv } from '../../util/chatEnvMirror';
import { a11yRuntimeState } from '../../util/a11yState';

// Dispatch only. Unsupported cases retain their existing behavior and sharing
// the image/cache services does not opt other message types into the new shell.
@ComponentV2
export struct TextMessageBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private env = chatEnv;
  private a11y = a11yRuntimeState;

  build() {
    if (this.env.drawnEnabled !== false && this.env.drawnText !== false && drawnTextRowEligible(this.group, this.data, this.env.bubbleMaterialOn, this.a11y.active)) {
      DrawnMessageRow({ kind: 'text', group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    } else {
      LegacyTextRow({ group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    }
  }
}
