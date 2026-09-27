# Cải thiện RAM và cold start

Ngày: 2026-09-27. Trạng thái: đã triển khai phần 1 (Welcome) và phần 2 (AI). Phần 3–6 chưa triển khai. Kiểm tra tương tác runtime còn chờ.

Không có bước đo baseline, theo yêu cầu của người dùng. Triển khai từng phần độc lập để dễ review và kiểm tra. Không đặt mục tiêu giảm MB hoặc thời gian cụ thể khi chưa có phép đo. Không tự launch/relaunch app.

## 1. Welcome

Điểm sửa chính: `WelcomeView`, `WelcomeDashboardModel`, `WelcomeActivityCache`.

- [x] Hiện activity cache trước khi chờ các truy vấn Git còn lại.
- [x] Ưu tiên repo đang hiển thị/gần đây; tiếp tục kiểm tra phần còn lại ở nền, không bỏ các cảnh báo hiện có.
- [x] Gộp các yêu cầu refresh liên tiếp; tránh nhiều lượt quét chồng nhau.
- [x] Notification có repository cụ thể chỉ invalidate/cập nhật repository đó; notification không xác định repo có fallback đầy đủ.
- [x] Hủy tác vụ cũ khi yêu cầu thay đổi hoặc view đóng; ngăn kết quả cũ ghi đè kết quả mới.
- [x] Reload thủ công vẫn kiểm tra đầy đủ và bỏ qua cache phù hợp.

Kiểm tra: nhiều repo, repo mất đường dẫn, notification dồn dập, đổi ngày, app active, Reload và đóng Welcome giữa lúc tải. Không làm mất attention của repo ngoài nhóm ưu tiên.

## 2. AI

Điểm sửa chính: `AIProviderController`, `macgitApp`, các màn hình chọn provider/Settings.

- [x] Bỏ kiểm tra toàn bộ provider từ Welcome khi không cần AI.
- [ ] Kiểm tra provider đang chọn khi mở tính năng AI; kiểm tra danh sách khi mở provider picker/Settings. Đã tách theo màn hình; danh sách hiện được kiểm tra khi control picker xuất hiện, chưa phải chỉ khi dropdown mở.
- [x] Trì hoãn đọc credential/configuration không cần cho màn hình đầu tiên.
- [x] Dùng chung một tác vụ refresh đang chạy; tránh lặp theo số window.
- [x] Invalidate đúng khi đổi credential, model, account hoặc entitlement.
- [x] Giữ kiểm tra quyền và availability tại thời điểm thực thi AI.

Kiểm tra: guest, signed-in, đổi provider/key, nhiều window, entitlement thay đổi và gửi yêu cầu ngay khi mở tính năng.

## 3. PR cache trên SQLite

Điểm sửa chính: `PullRequestController`, các model PR và lifecycle provider account.

- [ ] Tạo cache SQLite riêng trong thư mục cache của app, không dùng snapshot RAM của `LocalDataStore`.
- [ ] Đọc/ghi ngoài main thread; cache lỗi hoặc bị xóa phải fallback sang tải mạng.
- [ ] Cache list theo page; key chứa account, provider/host, repository, filter/sort và pagination.
- [ ] Cache detail riêng theo PR; changes/diff chỉ tải khi mở phần tương ứng.
- [ ] RAM chỉ giữ dữ liệu màn hình hiện tại; bỏ dictionary cache tích lũy trong controller.
- [ ] Có version schema, TTL, giới hạn tổng dung lượng disk và giới hạn mỗi entry; bỏ qua payload quá lớn.
- [ ] Dọn entry hết hạn và ít dùng; không quét/nạp toàn bộ payload để dọn cache.
- [ ] Cache hợp lệ hiển thị ngay; hết hạn refresh; Reload bỏ qua cache.
- [ ] Comment/merge/update invalidate đúng list/detail/changes liên quan.
- [ ] Xóa cache theo account khi logout/gỡ account; request cũ không được ghi lại cache sau khi xóa.
- [ ] Không lưu token/credential; không dùng dữ liệu account khác hoặc kết quả request đã lỗi thời.
- [ ] Điều chỉnh chức năng Clear Cache để bao phủ cache disk và trạng thái đang hiển thị phù hợp.

Kiểm tra: phân trang/filter, mở lại app, TTL, offline, cache hỏng, giới hạn dung lượng, mutation, đổi account, logout trong lúc request chạy và private PR giữa hai account.

## 4. Local storage

Điểm sửa chính: `LocalDataStore`, `LocalSQLiteDatabase`, `LocalDataTransaction` và các store sử dụng chúng.

- [ ] Liệt kê collection và consumer; xác định dữ liệu thật sự cần trước khi hiện màn hình đầu tiên.
- [ ] Thay đọc toàn bộ records bằng truy vấn theo collection/entity cần dùng.
- [ ] Chuyển các consumer sang tải bất đồng bộ hoặc snapshot có phạm vi rõ ràng; không đưa SQLite I/O vào main thread.
- [ ] Giữ serialization của writer và tính atomic của transaction nhiều collection.
- [ ] Giữ migration, verification, retry và thông báo lỗi; tránh mất dữ liệu khi import bị gián đoạn.
- [ ] Giải phóng snapshot không cần; tránh giải mã lại cùng dữ liệu trong mỗi lần render.

Kiểm tra: DB mới/cũ, migration lỗi giữa chừng, ghi đồng thời, transaction lỗi, dữ liệu nhiều collection và tải lại sau ghi. Đây là phần thay đổi contract, cần review riêng.

## 5. Cloud lifecycle

Điểm sửa chính: `macgitApp`, `AccountSessionController`, `FeatureAccessController` và các controller sync.

- [ ] Liệt kê dịch vụ/listener bắt đầu trong init và điều kiện thực sự cần chúng.
- [ ] Tách tạo đối tượng khỏi bắt đầu đồng bộ; trì hoãn phần không cần cho first window.
- [ ] Giữ bootstrap bắt buộc trước khi dùng Firebase API.
- [ ] Không làm yếu auth, entitlement, device enforcement hoặc feature policy trong thời gian chờ.
- [ ] Bảo đảm start idempotent; không nhân listener theo window.
- [ ] Hủy listener/task đúng khi đổi session; bỏ kết quả từ session cũ.

Kiểm tra: guest, session được khôi phục, offline, đăng nhập/đăng xuất, đổi account, nhiều window, policy và entitlement cập nhật. Phân biệt trì hoãn công việc với giảm RAM ổn định.

## 6. Cache và vòng đời còn lại

- [ ] History: giới hạn snapshot theo branch/filter; giữ selection và viewport khi background refresh.
- [ ] Branch/reference cache: giới hạn entry và invalidate sau mutation.
- [ ] Diff, preview, ảnh và thumbnail: giới hạn kích thước/số entry, tải theo nhu cầu và hủy khi đóng.
- [ ] Welcome activity: kiểm tra payload commit hash, giới hạn entry và giải phóng dữ liệu không hiển thị.
- [ ] AI chat: kiểm tra conversation/context/tool output được giữ lại và vòng đời controller.
- [ ] Undo: kiểm tra giới hạn/vòng đời nhưng không xóa dữ liệu cần cho undo còn hiệu lực.
- [ ] Window/controller: kiểm tra task, timer, observer, closure và subscription giữ đối tượng sau khi đóng.
- [ ] Ghi nhận từng mục đã có giới hạn hợp lý; không refactor chỉ để thay đổi kiến trúc.

Kiểm tra: mở/đóng nhiều repo, chuyển branch/filter, mở file lớn, chuyển PR, chat dài và undo/redo. Mỗi cache phải có owner, giới hạn, invalidation và điểm giải phóng rõ ràng.

## 7. Kiểm tra và bàn giao

- [ ] Mỗi phần có diff riêng dễ review, ghi rõ thay đổi và giới hạn kiểm chứng.
- [ ] Chạy coverage liên quan cho logic thay đổi; build/test tuần tự.
- [ ] Nếu XCTest abort lúc bootstrap/Firebase, không retry; báo test chưa chạy được.
- [ ] Build macOS không launch app và chạy `rtk git diff --check`.
- [ ] Đối chiếu chức năng: Welcome, AI, PR, local persistence, cloud access, History và undo.
- [ ] Ghi riêng các tương tác chưa kiểm tra runtime; build chỉ là bằng chứng biên dịch.
- [ ] Không khẳng định giảm RAM/cold start bằng con số khi chưa có phép đo thực tế. Nếu có số đo sau này, ghi rõ cấu hình và điều kiện; không dựng lại bước baseline đã bỏ.

Không tự commit, push hoặc thay đổi release. Các checkbox chỉ được đánh dấu khi có bằng chứng hoàn thành.

## Kết quả triển khai

### Phần 1 — Welcome (2026-09-27)

- Đọc cache cho toàn bộ tối đa 7 repo hiển thị trước khi bắt đầu các truy vấn activity còn thiếu; cập nhật từng repo khi tải xong.
- Attention vẫn kiểm tra toàn bộ recent repositories, ưu tiên repo mở gần đây và hiện cảnh báo dần. Kết quả đã kiểm tra được tái sử dụng đến khi invalidate.
- Notification có `repositoryURL` chỉ invalidate repo tương ứng; notification không có URL, đổi ngày và Reload invalidate đầy đủ. App active kiểm tra lại attention, giữ policy activity cache theo ngày.
- Các đợt refresh sau lần đầu được debounce 200 ms bằng task gắn với view; generation và cancellation guard chặn kết quả cũ, giữ invalidation chưa xử lý.
- Đã thêm `WelcomeDashboardRefreshTests` cho cache-first, invalidate theo repo, cảnh báo ngoài top 7, cancellation và force refresh.
- Build macOS: **PASS**. Test Welcome: **20/20 PASS**, gồm 5 test refresh mới và 15 test cache/dashboard/attention hiện có. Chưa launch/relaunch app để kiểm tra tương tác, chưa đo mức giảm RAM hoặc cold start.

### Phần 2 — AI (2026-09-27)

- Commit phần 1 trên branch `feature/improve-memory-and-app`: `7f1fb99` (`perf: streamline Welcome dashboard refreshes`).
- Bỏ đọc API key trong init và bỏ refresh toàn bộ provider từ Welcome khi khởi tạo/đổi account/entitlement.
- Các màn hình dùng AI yêu cầu availability của selection; provider menu khi xuất hiện và AI Settings yêu cầu toàn bộ danh sách để các lựa chọn có trạng thái đúng. Chưa chuyển việc kiểm tra danh sách sang đúng sự kiện dropdown mở; hiện gắn với vòng đời control hiển thị.
- Giữ đọc tên model từ UserDefaults để nhãn model và draft Settings đúng ngay khi hiện; không mở Keychain cho việc này.
- Các request availability đồng thời dùng chung task theo provider. Revision/identity loại kết quả cũ sau đổi account, entitlement, key hoặc model; UI AI đang hiển thị refresh theo revision.
- App active chỉ kiểm tra managed usage nếu provider đó từng được yêu cầu và session còn quyền sử dụng. Kiểm tra quyền khi thực thi AI được giữ nguyên.
- Build macOS: **PASS**. Các nhóm AIProviderAvailability, AICommitMessage, CloudAIProvider và CommitPlusAIUsageController: **44/44 PASS**.
- Chưa kiểm tra tương tác dropdown/nhiều window bằng runtime; chưa đo giảm RAM/cold start. Phần 2 hiện chưa commit.
