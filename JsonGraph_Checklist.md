# Json Graph Checklist

## Mục tiêu

- Thêm tab `Json Graph` vào `React Native Viewer`.
- Nghiên cứu theo source `jsoncrack.com` trước, chưa code feature ở tài liệu này.
- Tách rõ:
  - phần nào là `core graph engine`
  - phần nào là `editor / import-export / tooling` của website JsonCrack
- Ưu tiên tuyệt đối:
  - hiệu năng pan / zoom / hit-testing
  - tính chuyên dụng đồ hoạ native macOS
  - khả năng tiến hoá thành graph engine riêng cho app này

## Tóm tắt định hướng đã chốt

### Trạng thái: Hoàn thành

- [x] `Json Graph` sẽ không đi theo hướng nhúng web.
- [x] `Json Graph` sẽ đi theo hướng `AppKit/NSView/CALayer`.
- [x] Mục tiêu dài hạn không phải chỉ là “render được graph”, mà là tạo một engine native chuyên dụng cho:
  - scene graph
  - pan / zoom / selection
  - edge routing
  - label placement
  - culling / redraw tối ưu
- [x] SwiftUI chỉ nên đóng vai trò shell / toolbar / input / overlay; phần canvas và interaction loop phải nằm ở engine native riêng.

## Assumptions

- App là công cụ desktop macOS, không tối ưu cho iOS ở phase này.
- `Json Graph` cần ưu tiên trải nghiệm hơn tốc độ ra feature nhanh.
- Dữ liệu mục tiêu chủ yếu là JSON nhỏ đến vừa, nhưng engine phải có đường nâng cấp rõ cho JSON lớn.
- Mức mượt mong muốn:
  - pan / zoom ổn định
  - không blur bất thường
  - không giật khi drag
  - không tràn box / tràn viewport do sai cơ chế layout

## Decision Log

- Quyết định: Không dùng `WKWebView` / `jsoncrack-react` cho renderer chính.
  - Alternative: Nhúng web renderer để có UX tốt nhanh hơn.
  - Lý do chọn native: Bạn ưu tiên hiệu năng và tính chuyên dụng đồ hoạ cao nhất.
- Quyết định: Không vá tiếp trên kiến trúc `SwiftUI cards + NSScrollView + custom mouse math` hiện tại.
  - Alternative: Vá từng lỗi tràn viền / pan / zoom.
  - Lý do chọn refactor: Các lỗi hiện tại cho thấy renderer prototype đang sai tầng trừu tượng.
- Quyết định: Tạo engine riêng cho `Json Graph`.
  - Alternative: Giữ logic phân tán trong view SwiftUI hiện tại.
  - Lý do chọn engine riêng: Dễ kiểm soát scene, interaction, culling, testing và tối ưu hiệu năng về sau.

## Nghiên cứu từ source JsonCrack

### Trạng thái: Hoàn thành

- [x] Xác nhận repo `jsoncrack.com` hiện là monorepo.
- [x] Xác nhận app web chính nằm ở `apps/www`.
- [x] Xác nhận graph engine tái sử dụng nằm ở `packages/jsoncrack-react`.
- [x] Xác nhận `jsoncrack-react` dùng:
  - `jsonc-parser` để parse JSON thành tree
  - `reaflow` để render graph / layout
  - `react-zoomable-ui` để pan / zoom viewport
- [x] Xác nhận `jsoncrack-react` hỗ trợ sẵn:
  - parse input string hoặc object
  - graph node / edge
  - fit to view / focus root
  - collapse subtree
  - theme dark / light
  - direction layout
  - node limit để chặn graph quá lớn
- [x] Xác nhận website `jsoncrack.com` bọc thêm các lớp ngoài graph engine:
  - text editor
  - graph / tree mode
  - file/url/session workflow
  - convert format
  - export image
  - query / schema / codegen

## Kết luận nghiên cứu

### Trạng thái: Hoàn thành

- [x] `JsonCrack` không chỉ là 1 graph view; website thật gồm rất nhiều tooling bao quanh.
- [x] Phần cần học theo cho tab `Json Graph` trong app hiện tại là:
  - parse JSON thành graph
  - render graph có pan / zoom
  - hiển thị lỗi parse
  - xử lý object / array / primitive / null
  - collapse subtree nếu cần
- [x] Phần chưa nên bê nguyên vào phase đầu:
  - full editor kiểu Monaco
  - format conversion đa định dạng
  - jq / JSONPath / schema / codegen
  - export PNG / JPEG / SVG
- [x] Đây là điểm quan trọng:
  - source JsonCrack là React/TypeScript
  - app hiện tại là macOS SwiftUI
  - vì vậy không thể “copy thẳng” source JsonCrack vào app hiện tại theo cách native đơn giản

## Quyết định kỹ thuật cần chốt

### Trạng thái: Hoàn thành

- [x] Chốt hướng triển khai thực tế:
  - viết `graph engine native AppKit/NSView/CALayer` từ đầu để repo hiện tại tự build và test được ngay, không phụ thuộc bundle web ngoài.
- [x] Chốt scope phase 1:
  - nhận `JSON string`
  - cho phép lấy từ `Request Body / Response Body / paste tay`
  - chưa nhận trực tiếp từ `Compare Text`
- [x] Chốt yêu cầu UX:
  - tab riêng trong sidebar
  - 2 pane `input + graph`
  - render thủ công bằng nút `Render`
- [x] Chốt nguyên tắc kiến trúc:
  - `SwiftUI` chỉ làm shell UI
  - `AppKit/NSView/CALayer` làm canvas + interaction
  - tạo module / engine riêng cho xử lý graph thay vì gắn chặt vào màn `ConsoleDebuggerView`

## Checklist triển khai đề xuất

### Phase 1 - Scope và kiến trúc

- [x] Hoàn thành: Chốt hướng kỹ thuật `AppKit/NSView/CALayer graph renderer`.
- [x] Hoàn thành: Chốt nguồn dữ liệu đầu vào cho `Json Graph`.
- [x] Hoàn thành: Chốt behavior khi JSON lỗi cú pháp.
- [x] Hoàn thành: Chốt giới hạn dữ liệu lớn:
  - max input size
  - max node count
  - fallback UI khi quá lớn

### Phase 1.5 - Thiết kế engine native chuyên dụng

- [x] Hoàn thành: Đặt tên và phạm vi engine, ví dụ:
  - `RNVJsonGraphEngine`
  - `RNVJsonGraphSceneView`
  - `RNVJsonGraphLayoutEngine`
  - `RNVJsonGraphInteractionController`
- [x] Hoàn thành: Tách boundary rõ ràng:
  - parse model
  - layout engine
  - render scene
  - interaction / camera
  - selection / overlay data
- [x] Hoàn thành: Chốt data flow:
  - input JSON -> document model -> layout document -> render scene -> interaction state
- [x] Hoàn thành: Chốt non-goal cho engine phase đầu:
  - chưa làm animation phức tạp
  - chưa làm export ảnh
  - chưa làm editable graph

### Phase 2 - Core parse model

- [x] Hoàn thành: Thiết kế model nội bộ cho:
  - graph node
  - graph edge
  - path của node
  - row metadata
- [x] Hoàn thành: Parse được các kiểu:
  - object
  - array
  - string
  - number
  - boolean
  - null
- [x] Hoàn thành: Map object/array sang node con + edge label giống tinh thần JsonCrack.
- [x] Hoàn thành: Trả được parse error rõ ràng cho UI.

### Phase 3 - Graph rendering

- [x] Hoàn thành: Có prototype render graph theo layout ngang mặc định.
- [x] Hoàn thành: Có prototype pan / zoom / fit to view.
- [x] Hoàn thành: Có loading state khi graph đang dựng lại.
- [x] Hoàn thành: Có node limit guard để tránh treo app.
- [x] Hoàn thành: Có empty state khi chưa có JSON hợp lệ.

### Phase 3.5 - Thay prototype bằng engine AppKit/CALayer thật

- [x] Hoàn thành: Dựng `NSView` canvas riêng cho graph scene.
- [ ] Chưa làm: Dùng `CALayer` hoặc cây layer riêng cho:
  - node layer
  - edge layer
  - label layer
  - selection layer
- [ ] Chưa làm: Tạo camera model riêng:
  - translation
  - zoom scale
  - fit-to-view transform
  - zoom around cursor
- [ ] Chưa làm: Tạo interaction pipeline riêng:
  - pan
  - wheel zoom
  - trackpad zoom
  - click select
  - hover
- [ ] Chưa làm: Tối ưu redraw:
  - dirty-region aware nếu cần
  - layer reuse / pooling
  - tránh rebuild toàn scene mỗi lần đổi zoom
- [x] Hoàn thành: Tách overlay chi tiết node khỏi render canvas để không ảnh hưởng layout graph.

### Phase 3.6 - Node sizing và edge routing đúng chuẩn đồ hoạ

- [x] Hoàn thành: Đo kích thước node theo nội dung thật bằng AppKit text measurement.
- [x] Hoàn thành: Tính min/max width cho node theo loại dữ liệu.
- [x] Hoàn thành: Đảm bảo text wrapping / truncation được tính trước khi layout.
- [x] Hoàn thành: Tính lại content bounds bao gồm:
  - node box
  - edge label
  - stroke width
  - viewport padding
- [ ] Chưa làm: Bổ sung tránh va chạm cơ bản giữa edge label và node box.
- [x] Hoàn thành: Bổ sung clipping / masking đúng cho node, không để text tràn viền.

### Phase 4 - UI tab `Json Graph`

- [x] Hoàn thành: Thêm tab `Json Graph` vào `Left sidebar`.
- [x] Hoàn thành: Thiết kế screen tối thiểu cho phase đầu:
  - vùng nhập JSON
  - nút render
  - vùng graph
  - lỗi parse
- [x] Hoàn thành: Đồng bộ theme sáng hiện tại của app.
- [x] Hoàn thành: Ẩn các control không liên quan của `Logs / Network` khi ở tab này.

### Phase 5 - Data source integration

- [x] Hoàn thành: Cho phép đổ JSON từ text nhập tay.
- [x] Hoàn thành: Cho phép đổ nhanh từ `Network -> Request Body`.
- [x] Hoàn thành: Cho phép đổ nhanh từ `Network -> Response Body`.
- [ ] Chưa làm: Chốt có cần nhận dữ liệu từ `Compare Text` hay không.

### Phase 6 - Advanced parity với JsonCrack

- [ ] Chưa làm: Collapse / expand subtree.
- [ ] Chưa làm: Focus root node.
- [ ] Chưa làm: Direction layout có thể đổi `LEFT / RIGHT / UP / DOWN`.
- [x] Hoàn thành: Click node để xem chi tiết path / value.
- [ ] Chưa làm: Copy path / copy raw JSON fragment từ node.

### Phase 7 - Safety và hiệu năng

- [ ] Chưa làm: Benchmark với JSON nhỏ / vừa / lớn.
- [ ] Chưa làm: Chặn graph quá lớn bằng warning UI.
- [ ] Chưa làm: Kiểm tra memory footprint khi re-render nhiều lần.
- [ ] Chưa làm: Đảm bảo không block luồng chính của app khi parse dữ liệu lớn.

### Phase 7.5 - Re-assessment kiến trúc render

- [x] Hoàn thành: Xác định renderer native hiện tại có rủi ro kiến trúc:
  - node size đang cố định bằng hằng số, không đo theo nội dung thật
  - edge label chưa có collision avoidance với node box
  - content bounds mới tính theo khung node, chưa tính đủ cho edge label / stroke / overlay
  - pan / zoom đang ghép từ `SwiftUI + NSScrollView + custom mouse math`, dễ phát sinh glitch
  - zoom hiện vẫn là re-layout lại toàn scene native, không phải viewport transform tối ưu như web
- [x] Hoàn thành: Xác định vì sao web `jsoncrack` mượt hơn:
  - graph web dùng engine chuyên dụng cho graph view
  - text measurement, clipping, hit-testing và transform matrix được browser xử lý ổn định hơn
  - release notes của `jsoncrack` cho thấy họ đã đầu tư riêng vào `node size calculation`, `trackpad/zoom gestures`, và `web worker` cho layout
- [x] Hoàn thành: Chốt hướng đi tiếp theo:
  - bỏ phương án `WKWebView`
  - chọn `AppKit/NSView/CALayer`
  - tạo engine riêng thay cho tiếp tục vá prototype hiện tại
- [ ] Chưa làm: Tạo migration plan từ prototype hiện tại sang engine mới.
- [ ] Chưa làm: Chọn chiến lược thay thế:
  - rewrite một lần
  - hoặc dựng engine mới song song rồi swap tab `Json Graph` sau khi đủ tính năng tối thiểu

### Phase 8 - Test checklist

- [x] Hoàn thành: Test parse đúng object lồng nhau.
- [x] Hoàn thành: Test parse đúng array lồng nhau.
- [x] Hoàn thành: Test parse lỗi cú pháp.
- [x] Hoàn thành: Test node limit fallback.
- [x] Hoàn thành: Test lấy JSON từ `Request Body / Response Body`.
- [ ] Chưa làm: Test chuyển tab `Logs / Network / Json Graph` không mất trạng thái ngoài ý muốn.
- [ ] Chưa làm: Test layout engine trả về node bounds hợp lệ với nội dung dài.
- [ ] Chưa làm: Test content bounds luôn chứa đủ node + edge label.
- [ ] Chưa làm: Test zoom around cursor không làm lệch camera.
- [ ] Chưa làm: Test pan / zoom / select không phụ thuộc thứ tự redraw.
- [ ] Chưa làm: Test engine không rebuild toàn scene khi chỉ đổi camera transform.

## Đề xuất triển khai tiếp theo

### Trạng thái: Đang làm

- [x] Khuyến nghị bỏ tư duy “vá tiếp prototype”.
- [x] Khuyến nghị đi theo lộ trình:
  - chốt engine boundary
  - dựng scene view AppKit/CALayer tối thiểu
  - đo node theo nội dung thật
  - đưa camera transform vào engine
  - sau đó mới nối lại pan / zoom / selection / detail overlay
- [x] Chưa nên cố đạt parity 100% với website JsonCrack trước khi engine mới ổn định.

## Source tham khảo đã nghiên cứu

- Root repo: `https://github.com/AykutSarac/jsoncrack.com`
- Root README: `https://github.com/AykutSarac/jsoncrack.com/blob/main/README.md`
- Web app package: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/package.json`
- Editor page: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/src/pages/editor.tsx`
- Live editor host: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/src/features/editor/LiveEditor.tsx`
- File store: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/src/store/useFile.ts`
- JSON store: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/src/store/useJson.ts`
- `jsoncrack-react` README: `https://github.com/AykutSarac/jsoncrack.com/blob/main/packages/jsoncrack-react/README.md`
- `jsoncrack-react` parser: `https://github.com/AykutSarac/jsoncrack.com/blob/main/packages/jsoncrack-react/src/parser.ts`
- `jsoncrack-react` component: `https://github.com/AykutSarac/jsoncrack.com/blob/main/packages/jsoncrack-react/src/JSONCrackComponent.tsx`
- App graph wrapper: `https://github.com/AykutSarac/jsoncrack.com/blob/main/apps/www/src/features/editor/views/GraphView/index.tsx`
