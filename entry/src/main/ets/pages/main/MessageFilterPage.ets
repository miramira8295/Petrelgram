import { showToast } from '../../util/toast';
import {
  FilterMatchField, FilterMatchMode, MessageFilterRule, validateFilterPattern
} from '../../util/messageFilter';
import { getMessageFilterStore, MESSAGE_FILTER_EPOCH } from '../../store/MessageFilterStore';
import { getChatStore } from '../../tdkit/Globals';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { str } from '../../util/strings';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { EDGE_OVERLAY_VP, edgeBlurRadiusOf } from '../../util/scrollEdgeBlur';
import { ScrollEdgeBlurBinder } from '../../util/scrollEdgeBlurModifier';
import {
  EDGE_BLUR_BOTTOM_ON_DEFAULT, EDGE_BLUR_FOLLOW, EDGE_BLUR_ON_DEFAULT, EDGE_BLUR_TOP_ON_DEFAULT,
  KEY_EDGE_BLUR_BOTTOM_ON, KEY_EDGE_BLUR_ON, KEY_EDGE_BLUR_OTHER_BOTTOM, KEY_EDGE_BLUR_OTHER_TOP,
  KEY_EDGE_BLUR_TOP_ON, edgeBlurOtherBottomOn, edgeBlurOtherTopOn
} from '../../util/edgeBlurSetting';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

export interface MessageFilterRouteParam {
  chatId: number;
  chatTitle?: string;
}

@Builder
export function MessageFilterPageBuilder(): void {
  MessageFilterPage();
}

@Component
export struct MessageFilterPage {
  private edgeBlur: ScrollEdgeBlurBinder = new ScrollEdgeBlurBinder();
  private hdsScroller: Scroller = new Scroller();
  private navStack: NavPathStack | undefined = undefined;
  @State private blurViewH: number = 0;
  @StorageProp(KEY_EDGE_BLUR_ON) private edgeBlurOn: boolean = EDGE_BLUR_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_TOP_ON) private edgeBlurTopOn: boolean = EDGE_BLUR_TOP_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_BOTTOM_ON) private edgeBlurBottomOn: boolean = EDGE_BLUR_BOTTOM_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_OTHER_TOP) private edgeBlurOtherTop: string = EDGE_BLUR_FOLLOW;
  @StorageProp(KEY_EDGE_BLUR_OTHER_BOTTOM) private edgeBlurOtherBottom: string = EDGE_BLUR_FOLLOW;
  @StorageProp(LANGUAGE_EPOCH) private langEpoch: number = 0;
  @StorageProp(APPEARANCE_EPOCH) private appearanceEpoch: number = 0;
  @StorageProp('bottomSafeHeight') private bottomSafe: number = 0;
  @StorageProp(MESSAGE_FILTER_EPOCH) @Watch('reload') private filterEpoch: number = 0;

  @State private scopeChatId: number = 0;
  @State private scopeChatTitle: string = '';
  @State private masterEnabled: boolean = true;
  @State private globalDisabledHere: boolean = false;
  @State private rules: MessageFilterRule[] = [];
  @State private inheritedGlobalRules: MessageFilterRule[] = [];
  @State private customChats: number[] = [];

  @State private addSheetOpen: boolean = false;
  @State private draftField: FilterMatchField = 'keyword';
  @State private draftMode: FilterMatchMode = 'contains';
  @State private draftPattern: string = '';
  @State private draftError: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private applyRouteParams(param: Object | undefined): void {
    if (param !== undefined && typeof param === 'object') {
      const p: MessageFilterRouteParam = param as MessageFilterRouteParam;
      if (typeof p.chatId === 'number' && Number.isFinite(p.chatId)) {
        this.scopeChatId = p.chatId;
      }
      if (typeof p.chatTitle === 'string') {
        this.scopeChatTitle = p.chatTitle;
      }
    }
    this.reload();
  }

  private reload(): void {
    const store = getMessageFilterStore();
    this.masterEnabled = store.isEnabled();
    this.globalDisabledHere = this.scopeChatId !== 0 && store.isGlobalDisabledForChat(this.scopeChatId);
    this.rules = store.rulesForScope(this.scopeChatId);
    this.inheritedGlobalRules = (this.scopeChatId !== 0 && !this.globalDisabledHere)
      ? store.rulesForScope(0).filter((r: MessageFilterRule): boolean => r.enabled)
      : [];
    this.customChats = this.scopeChatId === 0 ? store.customChatIds() : [];
  }

  private chatTitleFor(chatId: number): string {
    const entry = getChatStore().entryOf(chatId);
    if (entry !== undefined && entry.title.trim() !== '') {
      return entry.title;
    }
    return `ID ${chatId}`;
  }

  private fieldLabel(field: FilterMatchField): string {
    if (field === 'user') {
      return str('mf_field_user');
    }
    if (field === 'nickname') {
      return str('mf_field_nickname');
    }
    return str('mf_field_keyword');
  }

  private modeLabel(mode: FilterMatchMode): string {
    if (mode === 'exact') {
      return str('mf_mode_exact');
    }
    if (mode === 'regex') {
      return str('mf_mode_regex');
    }
    return str('mf_mode_contains');
  }

  private rulePrimaryText(rule: MessageFilterRule): string {
    if (rule.field === 'user') {
      if (rule.pattern !== '') {
        return `@${rule.pattern}`;
      }
      if (rule.userId !== undefined && rule.userId > 0) {
        return `ID ${rule.userId}`;
      }
    }
    return rule.pattern;
  }

  private ruleSecondaryText(rule: MessageFilterRule): string {
    const parts: string[] = [this.fieldLabel(rule.field)];
    if (rule.field !== 'user') {
      parts.push(this.modeLabel(rule.mode));
    }
    if (rule.note !== undefined && rule.note !== '') {
      parts.push(rule.note);
    }
    return parts.join(' · ');
  }

  private openAddSheet(): void {
    this.draftField = 'keyword';
    this.draftMode = 'contains';
    this.draftPattern = '';
    this.draftError = '';
    this.addSheetOpen = true;
  }

  private submitNewRule(): void {
    const effectiveMode: FilterMatchMode = this.draftField === 'user' ? 'exact' : this.draftMode;
    if (!validateFilterPattern(this.draftField, effectiveMode, this.draftPattern)) {
      this.draftError = effectiveMode === 'regex' && this.draftPattern.trim() !== ''
        ? str('mf_err_invalid_regex')
        : str('mf_err_empty_pattern');
      return;
    }
    const added: boolean = getMessageFilterStore().addRule(
      this.scopeChatId, this.draftField, effectiveMode, this.draftPattern);
    if (added) {
      this.addSheetOpen = false;
      this.reload();
      showToast(str('mf_rule_added'), 1500);
    }
  }

  @Builder
  private sectionTitle(text: ResourceStr) {
    Text(text)
      .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accent())
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  @Builder
  private fieldChip(field: FilterMatchField, label: ResourceStr) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.draftField === field ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.draftField === field ? Color.White : COLOR_TEXT_PRIMARY)
      .backgroundColor(this.draftField === field ? this.accent() : $r('app.color.surface_alt'))
      .borderRadius(18)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .onClick((): void => {
        this.draftField = field;
        this.draftError = '';
      });
  }

  @Builder
  private modeChip(mode: FilterMatchMode, label: ResourceStr) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.draftMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.draftMode === mode ? this.accent() : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.draftMode === mode ? $r('app.color.surface_alt') : Color.Transparent)
      .borderRadius(14)
      .border({
        width: 1,
        color: this.draftMode === mode ? this.accent() : $r('app.color.divider')
      })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick((): void => {
        this.draftMode = mode;
        this.draftError = '';
      });
  }

  @Builder
  private addRuleSheet() {
    Column({ space: 14 }) {
      Text(str('mf_add_rule'))
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%');

      Row({ space: 8 }) {
        this.fieldChip('keyword', $r('app.string.mf_field_keyword'));
        this.fieldChip('nickname', $r('app.string.mf_field_nickname'));
        this.fieldChip('user', $r('app.string.mf_field_user'));
      }.width('100%');

      if (this.draftField !== 'user') {
        Row({ space: 8 }) {
          this.modeChip('contains', $r('app.string.mf_mode_contains'));
          this.modeChip('exact', $r('app.string.mf_mode_exact'));
          this.modeChip('regex', $r('app.string.mf_mode_regex'));
        }.width('100%');
      }

      TextInput({
        text: this.draftPattern,
        placeholder: this.draftField === 'user'
          ? str('mf_placeholder_user')
          : (this.draftField === 'nickname' ? str('mf_placeholder_nickname') : str('mf_placeholder_keyword'))
      })
        .height(46)
        .fontSize(16)
        .fontColor(COLOR_TEXT_PRIMARY)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((val: string): void => {
          this.draftPattern = val;
          if (this.draftError !== '') {
            this.draftError = '';
          }
        })
        .onSubmit((): void => { this.submitNewRule(); });

      if (this.draftError !== '') {
        Text(this.draftError)
          .fontSize(13).fontColor('#E53935')
          .width('100%');
      }

      Button(str('mf_add_confirm'))
        .width('100%').height(46)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
        .backgroundColor(this.accent())
        .borderRadius(23)
        .onClick((): void => { this.submitNewRule(); });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: this.bottomSafe + 24 });
  }

  @Builder
  private ruleRow(rule: MessageFilterRule) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.rulePrimaryText(rule))
          .fontSize(16).fontColor(rule.enabled ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Text(this.ruleSecondaryText(rule))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }.layoutWeight(1);

      if (this.scopeChatId !== 0) {
        Text(str('mf_promote_global'))
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.accent())
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(12)
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .onClick((): void => {
            if (getMessageFilterStore().promoteRuleToGlobal(rule.id)) {
              this.reload();
              showToast(str('mf_promoted_global_toast'), 1600);
            }
          });
      }

      Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
        .selectedColor(this.accent())
        .onChange((on: boolean): void => {
          getMessageFilterStore().toggleRule(rule.id, on);
        });

      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20).fontColor([COLOR_TEXT_SECONDARY])
        .padding(6)
        .onClick((): void => {
          getMessageFilterStore().removeRule(rule.id);
        });
    }
    .width('100%').padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    HdsSubDestination({
      title: this.scopeChatId !== 0 ? $r('app.string.mf_chat_title') : $r('app.string.mf_title'),
      subTitle: this.scopeChatId !== 0 ? this.scopeChatTitle : '',
      actionIcon: $r('sys.symbol.plus'),
      actionLabel: $r('app.string.mf_add_rule'),
      onAction: (): void => { this.openAddSheet(); },
      scroller: this.hdsScroller,
      onRouteParams: (param: Object | undefined): void => { this.applyRouteParams(param); },
      onNavStack: (stack: NavPathStack): void => { this.navStack = stack; }
    }) {
      Scroll(this.hdsScroller) {
        Column({ space: 14 }) {
          // 作用域开关卡片
          Column() {
            if (this.scopeChatId === 0) {
              Row() {
                Column({ space: 3 }) {
                  Text(str('mf_enable_global')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).width('100%');
                  Text(str('mf_enable_global_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                }.layoutWeight(1).margin({ right: 12 });
                Toggle({ type: ToggleType.Switch, isOn: this.masterEnabled })
                  .selectedColor(this.accent())
                  .onChange((on: boolean): void => {
                    getMessageFilterStore().setEnabled(on);
                  });
              }
              .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .alignItems(VerticalAlign.Center);
            } else {
              Row() {
                Column({ space: 3 }) {
                  Text(str('mf_apply_global')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).width('100%');
                  Text(str('mf_apply_global_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                }.layoutWeight(1).margin({ right: 12 });
                Toggle({ type: ToggleType.Switch, isOn: !this.globalDisabledHere })
                  .selectedColor(this.accent())
                  .onChange((on: boolean): void => {
                    getMessageFilterStore().setGlobalDisabledForChat(this.scopeChatId, !on);
                  });
              }
              .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .alignItems(VerticalAlign.Center);

              if (!this.masterEnabled) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                Text(str('mf_global_off_hint'))
                  .fontSize(13).fontColor('#E53935')
                  .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 12 });
              }
            }
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          // 规则列表卡片
          Column() {
            this.sectionTitle(this.scopeChatId !== 0 ? $r('app.string.mf_chat_rules_title') : $r('app.string.mf_rules_title'));
            if (this.rules.length === 0) {
              Column({ space: 10 }) {
                Text(str('mf_empty_hint'))
                  .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
                  .textAlign(TextAlign.Center).width('100%');
                Button(str('mf_add_rule'))
                  .height(38).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(Color.White).backgroundColor(this.accent())
                  .borderRadius(19).padding({ left: 18, right: 18 })
                  .onClick((): void => { this.openAddSheet(); });
              }
              .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 20 })
              .alignItems(HorizontalAlign.Center);
            } else {
              ForEach(this.rules, (rule: MessageFilterRule, idx: number) => {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                }
                this.ruleRow(rule);
              }, (rule: MessageFilterRule): string => `${rule.id}_${rule.enabled}_${this.langEpoch}`);
            }
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          // 单会话视图下展示继承自全局的生效规则，避免外层显示有规则、进来却看到空列表
          if (this.scopeChatId !== 0 && !this.globalDisabledHere && this.inheritedGlobalRules.length > 0) {
            Column() {
              Row() {
                Text($r('app.string.mf_inherited_global_title'))
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accent())
                  .layoutWeight(1);
                Text($r('app.string.mf_manage_global'))
                  .fontSize(13).fontColor(this.accent())
                  .onClick((): void => {
                    const param: MessageFilterRouteParam = { chatId: 0 };
                    this.navStack?.pushPath({ name: 'MessageFilterPage', param });
                  });
              }
              .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 })
              .alignItems(VerticalAlign.Center);

              ForEach(this.inheritedGlobalRules, (rule: MessageFilterRule, idx: number) => {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                }
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(this.rulePrimaryText(rule))
                      .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%');
                    Text(this.ruleSecondaryText(rule))
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%');
                  }.layoutWeight(1);
                  Text($r('app.string.mf_global_badge'))
                    .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
                    .backgroundColor($r('app.color.surface_alt'))
                    .borderRadius(10)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 });
                }
                .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center);
              }, (rule: MessageFilterRule): string => `g_${rule.id}_${this.langEpoch}`);
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });
          }

          // 全局视图下展示有独立配置的群组/频道列表
          if (this.scopeChatId === 0 && this.customChats.length > 0) {
            Column() {
              this.sectionTitle($r('app.string.mf_per_chat_section'));
              ForEach(this.customChats, (cid: number, idx: number) => {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                }
                Row() {
                  Column({ space: 2 }) {
                    Text(this.chatTitleFor(cid))
                      .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%');
                    Text(str('mf_chat_rule_summary',
                      String(getMessageFilterStore().rulesForScope(cid).length),
                      getMessageFilterStore().isGlobalDisabledForChat(cid)
                        ? str('mf_global_skipped') : str('mf_global_applied')))
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                      .width('100%');
                  }.layoutWeight(1);
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
                }
                .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  const param: MessageFilterRouteParam = {
                    chatId: cid,
                    chatTitle: this.chatTitleFor(cid)
                  };
                  this.navStack?.pushPath({ name: 'MessageFilterPage', param });
                });
              }, (cid: number): string => `${cid}_${this.filterEpoch}_${this.langEpoch}`);
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: EDGE_OVERLAY_VP + 8, bottom: this.bottomSafe + 24 });
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .onAreaChange((_old: Area, area: Area): void => {
        const h: number = Number(area.height);
        if (h > 0 && Math.abs(h - this.blurViewH) > 0.5) {
          this.blurViewH = h;
        }
      })
      .attributeModifier(this.edgeBlur.bind(
        edgeBlurRadiusOf(
          edgeBlurOtherTopOn(this.edgeBlurOn, this.edgeBlurTopOn, this.edgeBlurOtherTop) ||
          edgeBlurOtherBottomOn(this.edgeBlurOn, this.edgeBlurBottomOn, this.edgeBlurOtherBottom)
        ),
        this.blurViewH,
        edgeBlurOtherTopOn(this.edgeBlurOn, this.edgeBlurTopOn, this.edgeBlurOtherTop),
        edgeBlurOtherBottomOn(this.edgeBlurOn, this.edgeBlurBottomOn, this.edgeBlurOtherBottom)))
      .bindSheet($$this.addSheetOpen, this.addRuleSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: CARD_BG,
        onDisappear: (): void => { this.addSheetOpen = false; }
      });
    }
  }
}
