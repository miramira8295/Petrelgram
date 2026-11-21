import { KEY_APP_DARK } from '../../util/theme';
import { GLASS_OUTLINE_COLOR } from '../../util/bubbleTail';
import {
  KEY_SURFACE_GLASS_ON, SURFACE_GLASS_ON_DEFAULT, SURFACE_GLASS_EPOCH, surfaceGlassFill
} from '../../util/surfaceGlass';

// The header and the lazy list share a stationary surface.
// Settings repaint only this shell. Scrolling never changes its fill or geometry.
@Component
export struct HomeConversationPanel {
  @StorageProp(KEY_SURFACE_GLASS_ON) private glassOn: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private glassEpoch: number = 0;
  @StorageProp(KEY_APP_DARK) private dark: boolean = false;
  @BuilderParam header: () => void;
  @BuilderParam content: () => void;

  private panelFill(_epoch: number, _dark: boolean): ResourceColor {
    return this.glassOn ? surfaceGlassFill($r('app.color.surface')) : $r('app.color.surface');
  }

  build() {
    Column() {
      this.header();
      Stack({ alignContent: Alignment.TopStart }) {
        this.content();
      }
      .id('homeConversationViewport')
      .width('100%')
      .layoutWeight(1)
      .clip(true);
    }
    .id('homeConversationPanel')
    .width('100%')
    .height('100%')
    .backgroundColor(this.panelFill(this.glassEpoch, this.dark))
    .borderRadius(16)
    .border({ width: this.glassOn ? 0.5 : 0, color: GLASS_OUTLINE_COLOR })
    // Cached rows and spring overscroll cannot paint into the folder rail.
    .clip(true);
  }
}
