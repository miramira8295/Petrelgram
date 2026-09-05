import { describe, expect, it } from '@ohos/hypium';
import {
  normalizePhoneForDial, SharedLocationUris, sharedLocationUris
} from '../main/ets/util/locationActions';

// 上海外滩，够真实也够好读。
const LAT: number = 31.2304;
const LON: number = 121.4737;

export default function locationActionsTest() {
  // B3 从 ChatPage 的 `private openSharedPhone` 搬出来的第一段。
  describe('normalizePhoneForDial', () => {
    // vCard 里的号码几乎不会是干净的：空格、连字符、括号、国际前缀全都有。
    it('剥掉分隔符只留可拨字符', 0, (): void => {
      expect(normalizePhoneForDial('+86 138-0000-0000')).assertEqual('+8613800000000');
      expect(normalizePhoneForDial('(021) 6321 0000')).assertEqual('02163210000');
      expect(normalizePhoneForDial('  13800000000  ')).assertEqual('13800000000');
    });

    // `*` 和 `#` 必须留着：分机与运营商短码靠它们，`*100#` 被剥成 `100` 就拨不通了。
    it('保留 * 和 # 这类短码字符', 0, (): void => {
      expect(normalizePhoneForDial('*100#')).assertEqual('*100#');
      expect(normalizePhoneForDial('021-63210000,,1234')).assertEqual('021632100001234');
    });

    // 号码前后的说明文字会被整段吃掉，只剩数字——原实现如此。
    it('号码里夹的文字被剥掉', 0, (): void => {
      expect(normalizePhoneForDial('work: +86 138 0000 0000')).assertEqual('+8613800000000');
    });

    // 返回 '' 是页面弹「无电话号码」、**不**拉起拨号盘的依据。
    it('没有可拨字符时返回空串', 0, (): void => {
      expect(normalizePhoneForDial('')).assertEqual('');
      expect(normalizePhoneForDial('   ')).assertEqual('');
      expect(normalizePhoneForDial('no phone')).assertEqual('');
    });
  });

  // B3 从 ChatPage 的 `private openSharedLocation` 搬出来的拼串段。
  describe('sharedLocationUris', () => {
    // 坐标有效 + 有标签：geo 带真坐标，q 是标签；网页兜底走 mlat/mlon + #map=16。
    it('坐标有效时 geo 用真坐标、网页用 mlat/mlon', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, 'Bund Cafe', true);
      expect(uris.geoUri).assertEqual('geo:31.2304,121.4737?q=Bund%20Cafe');
      expect(uris.webFallback).assertEqual(
        'https://www.openstreetmap.org/?mlat=31.2304&mlon=121.4737#map=16/31.2304/121.4737');
    });

    // 没有标签时用坐标当搜索词。注意 encodeURIComponent 会把逗号编成 %2C——
    // 所以 q 里是 `31.2304%2C121.4737`，而 geo: 的路径部分仍是裸逗号。
    it('无标签时用坐标当搜索词，逗号被编码', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, '', true);
      expect(uris.geoUri).assertEqual('geo:31.2304,121.4737?q=31.2304%2C121.4737');
      expect(uris.webFallback).assertEqual(
        'https://www.openstreetmap.org/?mlat=31.2304&mlon=121.4737#map=16/31.2304/121.4737');
    });

    // 全空白的标签等同于没有标签（原实现先 trim）。
    it('全空白标签按无标签处理', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, '   ', true);
      expect(uris.geoUri).assertEqual('geo:31.2304,121.4737?q=31.2304%2C121.4737');
    });

    // 标签两端的空白被 trim 掉再编码。
    it('标签先 trim 再编码', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, '  Bund Cafe  ', true);
      expect(uris.geoUri).assertEqual('geo:31.2304,121.4737?q=Bund%20Cafe');
    });

    // 坐标无效但有标签：geo 退成 `0,0?q=<标签>`（"按名字搜"的老约定），
    // 网页退成 OSM 的 /search。
    it('坐标无效但有标签时退成按名字搜', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(0, 0, 'Bund Cafe', false);
      expect(uris.geoUri).assertEqual('geo:0,0?q=Bund%20Cafe');
      expect(uris.webFallback).assertEqual('https://www.openstreetmap.org/search?query=Bund%20Cafe');
    });

    // 坐标无效时即便消息里还带着经纬度也一律不用——原实现写死 `geo:0,0`。
    it('坐标无效时忽略传进来的经纬度', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, 'Bund Cafe', false);
      expect(uris.geoUri).assertEqual('geo:0,0?q=Bund%20Cafe');
      expect(uris.webFallback).assertEqual('https://www.openstreetmap.org/search?query=Bund%20Cafe');
    });

    // 【边界】坐标无效 + 标签为空 = 无事可做：原实现在这里直接弹「无位置信息」
    // 并 return，压根不拼 URI。纯函数照样什么都不给，页面按 geoUri === '' 走
    // 那条 toast 分支。别"顺手"改成照拼一个 geo:0,0?q= —— 那是把一次没有任何
    // 信息的搜索丢给地图 App。
    it('无坐标又无标签时两个 URI 都是空串', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(0, 0, '', false);
      expect(uris.geoUri).assertEqual('');
      expect(uris.webFallback).assertEqual('');
      const blank: SharedLocationUris = sharedLocationUris(0, 0, '   ', false);
      expect(blank.geoUri).assertEqual('');
      expect(blank.webFallback).assertEqual('');
    });

    // 与上一条成对：空判的闸是 `!valid && 标签为空`，**不是**"坐标等于 0,0"。
    // 坐标真的落在 0,0（Null Island）但 valid=true 时照样要拼出可用的 URI ——
    // 谁要是把守卫"简化"成 `latitude === 0 && longitude === 0`，这条会红。
    it('坐标有效时即便是 0,0 也照拼', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(0, 0, '', true);
      expect(uris.geoUri).assertEqual('geo:0,0?q=0%2C0');
      expect(uris.webFallback).assertEqual(
        'https://www.openstreetmap.org/?mlat=0&mlon=0#map=16/0/0');
    });

    // 标签里的 & # ? 必须被编码，否则会把 query 串截断/污染。
    it('标签里的 URL 元字符被编码', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(LAT, LON, 'A&B #1?', true);
      expect(uris.geoUri).assertEqual('geo:31.2304,121.4737?q=A%26B%20%231%3F');
    });

    // 负坐标（南半球 / 西半球）原样拼进去，不做任何格式化。
    it('负坐标原样拼进去', 0, (): void => {
      const uris: SharedLocationUris = sharedLocationUris(-33.8688, -70.6693, '', true);
      expect(uris.geoUri).assertEqual('geo:-33.8688,-70.6693?q=-33.8688%2C-70.6693');
      expect(uris.webFallback).assertEqual(
        'https://www.openstreetmap.org/?mlat=-33.8688&mlon=-70.6693#map=16/-33.8688/-70.6693');
    });
  });
}
