import { SearchSegment, searchSegments } from '../../util/searchPresentation';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';

@Component
export struct SearchHitText {
  @Prop text: string = '';
  @Prop query: string = '';
  @Prop textSize: number = 14;
  @Prop lines: number = 2;
  @Prop color: ResourceColor = COLOR_TEXT_PRIMARY;
  build() {
    Text() {
      ForEach(searchSegments(this.text, this.query), (part: SearchSegment) => {
        Span(part.text).fontColor(part.hit ? COLOR_PRIMARY : this.color)
          .fontWeight(part.hit ? FontWeight.Bold : FontWeight.Normal);
      }, (part: SearchSegment, index: number): string => `${index}:${part.hit}:${part.text}`);
    }
    .fontSize(this.textSize).maxLines(this.lines).textOverflow({ overflow: TextOverflow.Ellipsis });
  }
}
