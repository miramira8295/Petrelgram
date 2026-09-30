// 群组/频道成员列表顶上的搜索框。只管输入和防抖，真正的搜索在
// ChatProfileStore.searchMembers（服务端按名字和用户名匹配）。
//
// 防抖 300ms：每敲一个字就发一次 searchChatMembers，大群里既费流量又会让
// 列表一闪一闪；停手之后再搜。清空按钮不走防抖，立刻回到完整名单。
import { COLOR_ICON_SECONDARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const SEARCH_DEBOUNCE_MS: number = 300;
const FIELD_HEIGHT: number = 38;

@ComponentV2
export struct MemberSearchField {
  @Event onQuery: (query: string) => void = (_q: string): void => {};
  @Local private text: string = '';
  private timer: number = -1;

  aboutToDisappear(): void {
    this.cancelTimer();
  }

  private cancelTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private onInput(value: string): void {
    this.text = value;
    this.cancelTimer();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.onQuery(value);
    }, SEARCH_DEBOUNCE_MS);
  }

  private clear(): void {
    this.cancelTimer();
    this.text = '';
    this.onQuery('');
  }

  build() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
      TextInput({ placeholder: $r('app.string.cpp_search_members'), text: this.text })
        .layoutWeight(1).height(FIELD_HEIGHT)
        .padding(0)
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .backgroundColor(Color.Transparent)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string): void => { this.onInput(value); });
      if (this.text !== '') {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(16).fontColor([COLOR_ICON_SECONDARY])
          .onClick((): void => { this.clear(); });
      }
    }
    .width('100%').height(FIELD_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(FIELD_HEIGHT / 2)
    .backgroundColor($r('app.color.reaction_chip'))
    .alignItems(VerticalAlign.Center);
  }
}
