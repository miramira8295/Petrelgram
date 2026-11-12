import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnMessageRow } from './DrawnMessageRow';
import { LegacySingleMediaBubble } from './LegacySingleMediaBubble';
import { drawnSingleMediaEligible } from '../../util/drawnSingleMediaPolicy';
import { chatEnv } from '../../util/chatEnvMirror';
import { a11yRuntimeState } from '../../util/a11yState';

@ComponentV2
export struct SingleMediaBubble {
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
    if (this.env.drawnEnabled !== false && this.env.drawnSingle !== false && drawnSingleMediaEligible(this.group, this.env.bubbleMaterialOn, this.a11y.active)) {
      DrawnMessageRow({ kind: 'single', group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    } else {
      LegacySingleMediaBubble({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    }
  }
}
