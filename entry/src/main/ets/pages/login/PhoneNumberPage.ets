import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount, waitForConnection
} from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  CountryOption, fallbackCountries, filterCountries, loadCountries
} from './CountryData';
import { LoginHero } from './LoginHero';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logW } from '../../util/log';

@Preview
@Component
export struct PhoneNumberPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 窗口是全屏沉浸的（EntryAbility.setWindowLayoutFullScreen），页面自己让出
  // 状态栏高度，否则标题会压在时钟和信号图标底下。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageChanged') langEpoch: number = 0;
  @State phoneDigits: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;
  // 请求已排队、正在等 TDLib 把连接建起来。按钮上要有反馈，否则这几秒看起来
  // 像点了没反应。
  @State connecting: boolean = false;
  @State pickerOpen: boolean = false;
  @State pickerReady: boolean = false;
  @State countrySearch: string = '';
  @State countries: CountryOption[] = fallbackCountries();
  @State selectedCountry: CountryOption = {
    iso2: 'CN',
    name: str('country_cn'),
    englishName: 'China',
    callingCode: '86',
    flag: '🇨🇳'
  };

  aboutToAppear(): void {
    this.reloadCountries();
  }

  // 国家名两条来源都跟当前语言走：str() 的兜底表和 TDLib 的 getCountries。
  // 语言一变整张表都得重取 —— countries/selectedCountry 是构造时求值的
  // @State，不重取就会停在旧语言上。
  private onLanguageChanged(): void {
    this.countries = fallbackCountries();
    this.adoptSelection();
    this.reloadCountries();
  }

  private reloadCountries(): void {
    loadCountries().then((countries: CountryOption[]): void => {
      this.countries = countries;
      this.adoptSelection();
    });
  }

  // 选中项按 iso2+区号 认，在新列表里换成同一条的新语言版本。用户手选过的
  // 国家因此不会被重取悄悄改掉。
  private adoptSelection(): void {
    const iso2: string = this.selectedCountry.iso2;
    const callingCode: string = this.selectedCountry.callingCode;
    const match = this.countries.find(
      (item: CountryOption): boolean => item.iso2 === iso2 && item.callingCode === callingCode
    );
    if (match !== undefined) {
      this.selectedCountry = match;
    }
  }

  private onPhoneChange(value: string): void {
    const digits = value.replace(/[^0-9]/g, '');
    this.phoneDigits = digits.substring(0, Math.min(15, digits.length));
    this.errorText = '';
  }

  private submitPhone(): void {
    if (this.busy) { return; }
    if (this.phoneDigits.length < 4) {
      this.errorText = str('lg_invalid_phone');
      return;
    }
    const fullPhone = `+${this.selectedCountry.callingCode}${this.phoneDigits}`;
    this.runWhenConnected((): Promise<void> => getAuthService().submitPhone(fullPhone));
  }

  // 状态流转到 WaitQrCode 后 Index 会切到扫码页，这里只需负责发起请求。
  private startQrLogin(): void {
    this.runWhenConnected((): Promise<void> => getAuthService().requestQrLogin());
  }

  // 两个登录入口共用：先等连接建起来再发请求。冷启动时 TDLib 的 DC 握手还没
  // 完成，这时候发出去的请求只会挂到 15 秒超时然后报错；用户摸索出的"先选一
  // 下区域再点就好"，其实就是选区域那几秒把握手等过去了。
  private runWhenConnected(action: () => Promise<void>): void {
    if (this.busy) { return; }
    this.busy = true;
    this.connecting = true;
    this.errorText = '';
    waitForConnection().then((connected: boolean): Promise<void> => {
      this.connecting = false;
      if (!connected) {
        // 等不到就照发：让 TDLib 给出真实原因，而不是我们编一个。
        logW('PhoneNumberPage: sending login request without a ready connection');
      }
      return action();
    }).catch((caught: TdError): void => {
      this.errorText = caught.message;
    }).finally((): void => {
      this.busy = false;
      this.connecting = false;
    });
  }

  private continueLabel(): ResourceStr {
    if (this.connecting) { return $r('app.string.proxy_state_connecting'); }
    return this.busy ? $r('app.string.lg_sending_code') : $r('app.string.lg_continue');
  }

  private selectCountry(country: CountryOption): void {
    if (!this.pickerReady) { return; }
    this.selectedCountry = country;
    this.countrySearch = '';
    this.pickerReady = false;
    this.pickerOpen = false;
    this.errorText = '';
  }

  private openCountryPicker(): void {
    this.pickerReady = false;
    this.pickerOpen = true;
    setTimeout((): void => {
      if (this.pickerOpen) { this.pickerReady = true; }
    }, 800);
  }

  @Builder
  countryPickerSheet() {
    Column() {
      Row() {
        Text($r('app.string.lg_pick_country'))
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
      }
      .padding({ left: 18, right: 58, bottom: 12 })
      .margin({left: 12, right: 12, bottom: 12, top: 12})
      .alignItems(VerticalAlign.Center);

      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
        TextInput({ text: this.countrySearch, placeholder: $r('app.string.lg_search_country') })
          .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(42)
          .onChange((value: string): void => { this.countrySearch = value; });
      }
      .padding({ left: 13, right: 10 })
      .margin({ left: 14, right: 14, bottom: 8 })
      .borderRadius(13)
      .backgroundColor($r('app.color.page_bg'));

      List() {
        ForEach(
          filterCountries(this.countries, this.countrySearch),
          (country: CountryOption) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(country.flag).fontSize(27).width(36).textAlign(TextAlign.Center);
                Column({ space: 2 }) {
                  Text(country.name)
                    .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  if (country.englishName !== '' && country.englishName !== country.name) {
                    Text(country.englishName)
                      .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
                Text(`+${country.callingCode}`).fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
                if (country.iso2 === this.selectedCountry.iso2 &&
                  country.callingCode === this.selectedCountry.callingCode) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16).fontColor([COLOR_PRIMARY]);
                }
              }
              .width('100%')
              .padding({ left: 16, right: 18, top: 10, bottom: 10 })
              .onClick((): void => this.selectCountry(country));
            }
          },
          // 键里带上国名：ForEach 对键没变的项直接复用旧节点，切了语言
          // 名字不会更新。
          (country: CountryOption): string =>
            `${country.iso2}_${country.callingCode}_${country.name}`
        );
      }
      .layoutWeight(1)
      .enabled(this.pickerReady)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%').height('100%')
    .padding({ top: 12, bottom: 12 });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'phone' });

        Text($r('app.string.lg_your_phone'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.lg_phone_hint'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .lineHeight(21)
          .padding({ left: 20, right: 20 });

        Row({ space: 10 }) {
          Text(this.selectedCountry.flag).fontSize(24);
          Text(this.selectedCountry.name)
            .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(`+${this.selectedCountry.callingCode}`)
            .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width('100%').height(54)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(13)
        .border({ width: 1, color: '#263390EC' })
        .onClick((): void => this.openCountryPicker());

        Row({ space: 10 }) {
          Row() {
            Text(`+${this.selectedCountry.callingCode}`)
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          }
          .height(54).padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(13)
          .border({ width: 1, color: '#263390EC' });

          TextInput({ text: this.phoneDigits, placeholder: $r('app.string.ct_phone') })
            .type(InputType.PhoneNumber)
            .fontSize(17).fontColor(COLOR_TEXT_PRIMARY)
            .placeholderColor(COLOR_TEXT_SECONDARY)
            .caretColor(COLOR_PRIMARY)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(13)
            .border({ width: 1, color: this.errorText !== '' ? '#FF3B30' : '#263390EC' })
            .height(54).padding({ left: 14, right: 14 })
            .layoutWeight(1)
            .enterKeyType(EnterKeyType.Go)
            .onChange((value: string): void => this.onPhoneChange(value))
            .onSubmit((): void => this.submitPhone());
        }
        .width('100%');

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%')
            .fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button(this.continueLabel())
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(14)
          .enabled(!this.busy && this.phoneDigits.length >= 4)
          .onClick((): void => this.submitPhone());

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(18).fontColor([COLOR_PRIMARY]);
          Text($r('app.string.lg_qr_sign_in'))
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
        }
        .width('100%').height(46)
        .justifyContent(FlexAlign.Center)
        .enabled(!this.busy)
        .onClick((): void => this.startQrLogin());

        if (canReturnToPreviousTdAccount()) {
          Button($r('app.string.lg_back_to_account'))
            .width('100%').height(46)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = caught.message;
                this.busy = false;
              });
            });
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 24, right: 24, top: this.topSafe + 28, bottom: 28 });
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'))
    .bindSheet($$this.pickerOpen, this.countryPickerSheet(), {
      height: '82%',
      backgroundColor: $r('app.color.surface'),
      dragBar: true,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}
