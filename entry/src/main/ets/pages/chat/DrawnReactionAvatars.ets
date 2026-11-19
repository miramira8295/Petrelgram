import { ReactionSender, reactionAvatarWidth } from '../../util/reactionSenders';
import { DrawnReactionAvatarsPainter } from './DrawnReactionAvatarsPainter';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { chatEnv } from '../../util/chatEnvMirror';
import { logW } from '../../util/log';

@ComponentV2
export struct DrawnReactionAvatars {
  @Require @Param senders: ReactionSender[];
  @Param ownerKey: string = '';
  private painter: DrawnReactionAvatarsPainter = new DrawnReactionAvatarsPainter();
  private attached: boolean = false;
  @Computed private get environment(): string {
    return `${chatEnv.appearanceEpoch}:${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  private bind(): void {
    if (!this.attached) { return; }
    try { this.painter.bind(this.getUIContext(), this.senders, this.ownerKey, this.environment); }
    catch (error) { this.painter.dispose(); logW(`Reaction avatars: ${(error as Error).message}`); }
  }
  @Monitor('senders', 'ownerKey', 'environment') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.attached = true; this.bind(); }
  aboutToReuse(): void { this.attached = true; this.bind(); }
  aboutToRecycle(): void { this.attached = false; this.painter.dispose(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  build() {
    Row().width(reactionAvatarWidth(Math.min(3, this.senders.length))).height(20).clip(true)
      .drawModifier(this.painter).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
