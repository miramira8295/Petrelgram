import { navigationHaptics } from '../../services/NavigationHaptics';
import { setBoolean, setNumber } from '../../store/AppSettings';
import { KEY_FOLDER_HAPTIC_ON, KEY_DOCK_HAPTIC_ON, KEY_FOLDER_HAPTIC_STRENGTH,
  KEY_DOCK_HAPTIC_STRENGTH, NAVIGATION_HAPTIC_DEFAULT, normalizeNavigationHapticStrength } from '../../util/navigationHapticSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

@Component
struct NavigationHapticCard {
  @Prop category: string = 'folder';
  @Prop feedbackOn: boolean = true;
  @Prop feedbackStrength: number = NAVIGATION_HAPTIC_DEFAULT;
  @Prop cardLabel: ResourceStr = '';

  private enabledKey(): string { return this.category === 'folder' ? KEY_FOLDER_HAPTIC_ON : KEY_DOCK_HAPTIC_ON; }
  private strengthKey(): string { return this.category === 'folder' ? KEY_FOLDER_HAPTIC_STRENGTH : KEY_DOCK_HAPTIC_STRENGTH; }

  build() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(this.cardLabel).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.feedbackOn }).selectedColor(COLOR_PRIMARY)
          .accessibilityText(this.category === 'folder' ? $r('app.string.ix_folder_haptic') : $r('app.string.ix_dock_haptic'))
          .onChange((on: boolean): void => {
            this.feedbackOn = on;
            setBoolean(this.enabledKey(), on);
            if (on) { navigationHaptics.play(this.category); }
          });
      }.width('100%');
      if (this.feedbackOn) {
        Row({ space: 12 }) {
          Text(str('ix_haptic_strength', String(this.feedbackStrength)))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
          Button($r('app.string.ix_haptic_preview')).fontSize(13)
            .fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
            .onClick((): void => { navigationHaptics.play(this.category); });
        }.width('100%');
        Slider({ value: this.feedbackStrength, min: 1, max: 100, step: 1 })
          .selectedColor(COLOR_PRIMARY).width('100%')
          .accessibilityText($r('app.string.ix_haptic_strength_label'))
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.feedbackStrength = normalizeNavigationHapticStrength(value);
            // Dragging updates only the local label. Persist and preview once
            // on release/click, without motor calls or disk writes per frame.
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              setNumber(this.strengthKey(), this.feedbackStrength);
              navigationHaptics.play(this.category);
            }
          });
      }
    }.width('100%').padding({ left: 16, right: 13, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface')).borderRadius(14);
  }
}

@Component
export struct NavigationHapticSettings {
  @StorageProp(KEY_FOLDER_HAPTIC_ON) folderOn: boolean = true;
  @StorageProp(KEY_DOCK_HAPTIC_ON) dockOn: boolean = true;
  @StorageProp(KEY_FOLDER_HAPTIC_STRENGTH) folderStrength: number = NAVIGATION_HAPTIC_DEFAULT;
  @StorageProp(KEY_DOCK_HAPTIC_STRENGTH) dockStrength: number = NAVIGATION_HAPTIC_DEFAULT;

  aboutToAppear(): void { navigationHaptics.prepare(); }

  build() {
    Column({ space: 14 }) {
      NavigationHapticCard({ category: 'folder', feedbackOn: this.folderOn, feedbackStrength: this.folderStrength,
        cardLabel: $r('app.string.ix_folder_haptic') });
      NavigationHapticCard({ category: 'dock', feedbackOn: this.dockOn, feedbackStrength: this.dockStrength,
        cardLabel: $r('app.string.ix_dock_haptic') });
      Text($r('app.string.ix_haptic_note')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16 });
    }.width('100%');
  }
}
