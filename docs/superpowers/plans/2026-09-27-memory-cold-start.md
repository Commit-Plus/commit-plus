# Cải thiện RAM và cold start

Ngày: 2026-09-27. Trạng thái: đã triển khai phần 1 (Welcome), phần 2 (AI, còn mục dropdown), phần 3 (PR cache), phần 4 (local storage), phần 5 (cloud lifecycle) và phần 6 (cache/lifecycle còn lại). Kiểm tra tương tác runtime còn chờ.

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

- [x] Tạo cache SQLite riêng trong thư mục cache của app, không dùng snapshot RAM của `LocalDataStore`.
- [x] Đọc/ghi ngoài main thread; cache lỗi hoặc bị xóa phải fallback sang tải mạng.
- [x] Cache list theo page; key chứa account, provider/host, repository, filter/sort và pagination.
- [x] Cache detail riêng theo PR; changes/diff chỉ tải khi mở phần tương ứng.
- [x] RAM chỉ giữ dữ liệu màn hình hiện tại; bỏ dictionary cache tích lũy trong controller.
- [x] Có version schema, TTL, giới hạn tổng dung lượng disk và giới hạn mỗi entry; bỏ qua payload quá lớn.
- [x] Dọn entry hết hạn và ít dùng; không quét/nạp toàn bộ payload để dọn cache.
- [x] Cache hợp lệ hiển thị ngay; hết hạn refresh; Reload bỏ qua cache.
- [x] Comment/merge/update invalidate đúng list/detail/changes liên quan.
- [x] Xóa cache theo account khi logout/gỡ account; request cũ không được ghi lại cache sau khi xóa.
- [x] Không lưu token/credential; không dùng dữ liệu account khác hoặc kết quả request đã lỗi thời.
- [x] Điều chỉnh chức năng Clear Cache để bao phủ cache disk và trạng thái đang hiển thị phù hợp.

Kiểm tra: phân trang/filter, mở lại app, TTL, offline, cache hỏng, giới hạn dung lượng, mutation, đổi account, logout trong lúc request chạy và private PR giữa hai account.

## 4. Local storage

Điểm sửa chính: `LocalDataStore`, `LocalSQLiteDatabase`, `LocalDataTransaction` và các store sử dụng chúng.

- [x] Liệt kê collection và consumer; xác định dữ liệu thật sự cần trước khi hiện màn hình đầu tiên.
- [x] Thay đọc toàn bộ records bằng truy vấn theo collection/entity cần dùng.
- [x] Chuyển các consumer sang tải bất đồng bộ hoặc snapshot có phạm vi rõ ràng; không đưa SQLite I/O vào main thread.
- [x] Giữ serialization của writer và tính atomic của transaction nhiều collection.
- [x] Giữ migration, verification, retry và thông báo lỗi; tránh mất dữ liệu khi import bị gián đoạn.
- [x] Giải phóng snapshot không cần; tránh giải mã lại cùng dữ liệu trong mỗi lần render.

Kiểm tra: DB mới/cũ, migration lỗi giữa chừng, ghi đồng thời, transaction lỗi, dữ liệu nhiều collection và tải lại sau ghi. Đây là phần thay đổi contract, cần review riêng.

## 5. Cloud lifecycle

Điểm sửa chính: `macgitApp`, `AccountSessionController`, `FeatureAccessController` và các controller sync.

- [x] Liệt kê dịch vụ/listener bắt đầu trong init và điều kiện thực sự cần chúng.
- [x] Tách tạo đối tượng khỏi bắt đầu đồng bộ; trì hoãn phần không cần cho first window.
- [x] Giữ bootstrap bắt buộc trước khi dùng Firebase API.
- [x] Không làm yếu auth, entitlement, device enforcement hoặc feature policy trong thời gian chờ.
- [x] Bảo đảm start idempotent; không nhân listener theo window.
- [x] Hủy listener/task đúng khi đổi session; bỏ kết quả từ session cũ.

Kiểm tra: guest, session được khôi phục, offline, đăng nhập/đăng xuất, đổi account, nhiều window, policy và entitlement cập nhật. Phân biệt trì hoãn công việc với giảm RAM ổn định.

## 6. Cache và vòng đời còn lại

- [x] History: giới hạn snapshot theo branch/filter; giữ selection và viewport khi background refresh.
- [x] Branch/reference cache: giới hạn entry và invalidate sau mutation.
- [x] Diff, preview, ảnh và thumbnail: giới hạn kích thước/số entry, tải theo nhu cầu và hủy khi đóng.
- [x] Welcome activity: kiểm tra payload commit hash, giới hạn entry và giải phóng dữ liệu không hiển thị.
- [x] AI chat: kiểm tra conversation/context/tool output được giữ lại và vòng đời controller.
- [x] Undo: kiểm tra giới hạn/vòng đời nhưng không xóa dữ liệu cần cho undo còn hiệu lực.
- [x] Window/controller: kiểm tra task, timer, observer, closure và subscription giữ đối tượng sau khi đóng.
- [x] Ghi nhận từng mục đã có giới hạn hợp lý; không refactor chỉ để thay đổi kiến trúc.

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

### Phần 3 — PR cache SQLite (2026-09-27)

- `PullRequestDiskCache` là actor riêng, đọc/ghi/encode/decode SQLite ngoài main actor, không dùng `LocalDataStore` và không giữ dictionary payload trong RAM.
- List/detail/changes được cache theo account, provider, host, repository, loại dữ liệu và page/filter hoặc số PR. Sort của provider hiện cố định; created-by-me là filter trên page đang hiển thị.
- TTL giữ như trước: list 120 giây, detail/changes 300 giây. Giới hạn 32 MiB payload, 300 entry, 2 MiB/entry; SQLite tự thu hồi page và giới hạn 10.240 page. Payload quá lớn vẫn trả về UI, không lưu cache.
- Dọn hết hạn và entry ít dùng bằng metadata SQL; cache lỗi là cache miss. Clear Cache/logout có thể xóa cache hỏng. File cache có permission 0600; không serialize token.
- Bỏ ba dictionary cache trong PR controller. View giải phóng list/detail/changes khi rời màn hình, lần sau đọc lại disk; request ID chặn response từ selection/view/account cũ. Epoch trong cache chặn ghi lại dữ liệu sau invalidation.
- Comment/create/merge giữ invalidation và force-refresh hiện có. Clear Cache bao gồm SQLite kể cả khi không có cửa sổ repo; màn hình PR đang mở tải lại từ mạng.
- Gỡ provider account xóa cache tương ứng. Logout/đổi tài khoản Commit+ xóa cache phiên trước; khôi phục auth ban đầu không xóa cache hợp lệ. Tests dùng DB tạm riêng.
- Đã kiểm tra persistence qua cache/controller mới, TTL, giới hạn/oversize, corruption, namespace account/repo/filter/page và response đến muộn sau Clear Cache.
- Validation cuối trên mã bàn giao: **BUILD SUCCEEDED**, **85/85 test PASS**, `git diff --check` sạch. Không đo baseline, không tự mở lại app để kiểm tra UI. Chưa commit phần 3.

### Phần 4 — Local storage (2026-09-27)

- `prepare()` chỉ giữ ba collection nhỏ phục vụ API định tuyến credential đồng bộ; bỏ snapshot RAM của toàn bộ database.

| Collection | Consumer và thời điểm đọc |
| --- | --- |
| `providerAccounts`, `providerPreferences`, `sshPaths` | Account/credential routing; snapshot resident sau prepare |
| `repoSettings` | RepoSettingsStore và commit-rule sync; đọc theo repository khi cần |
| `bookmarks`, `bookmarkPaths`, `bookmarkUploads`, `bookmarkDeletes` | Bookmark controller; snapshot có phạm vi khi load/sync, giữ model UI cần hiển thị |
| `providerDeletions`, `providerSyncedIdentities` | Provider account sync; đọc khi reconcile |
| `repositoryVisibility` | Visibility controller; đọc theo repository |
| `gitFlowPending`, `commitRulePending` | Sync controller; đọc marker khi đồng bộ |

- SQLite I/O vẫn chạy trên actor database. Snapshot transaction chỉ chứa collection được khai báo, được giải phóng sau thao tác; writer vẫn serialize và commit nhiều collection atomically. Resident snapshot chỉ cập nhật sau commit thành công.
- Migration vẫn import trong transaction và kiểm tra từng record trước khi đánh dấu hoàn tất; không nạp toàn bộ database để verification. Lỗi đọc pending marker được chuyển tới xử lý lỗi sync để tránh hiểu nhầm là không có thay đổi local.
- Thêm coverage cho đọc có phạm vi, không giữ collection không liên quan, rollback khi đọc thiếu scope, ghi đồng thời và cập nhật resident snapshot.
- Validation: build macOS **PASS**, **60/60 test PASS** trong các nhóm local storage, migration, bookmark, settings, sync, visibility và credential stores; commit-rule sync sau thay đổi cuối **4/4 test PASS**. Không launch/relaunch app; chưa đo mức giảm RAM/cold start.

### Phần 5 — Cloud lifecycle (2026-09-27)

- Phase 4 đã commit tại `33166a1` (`perf: load local data on demand`).
- Inventory khởi động: Firebase bootstrap và khôi phục/claim device vẫn chạy trước khi công bố authenticated session; entitlement và settings sync chỉ bắt đầu sau session hợp lệ. Git Flow và commit-rule cloud store chỉ làm I/O khi repository dùng tính năng tương ứng. AI managed usage vẫn tải theo nhu cầu.
- Feature policy dùng ngay cached/bundled policy nhưng chỉ mở live listener sau khi first window hoàn tất initial setup. `start()` idempotent nên nhiều window không nhân listener.
- Provider-account và bookmark sync được chuyển khỏi từng `ContentView` sang `AppCloudLifecycleController` cấp app. Cùng một session chỉ reconcile một lần; provider và bookmark hydrate song song. Khi session đổi trong lúc đang sync, workflow hoàn tất thao tác shared-store đang chạy, bỏ session trung gian đã lỗi thời và chỉ áp dụng session mới nhất.
- Device observation, entitlement observation và settings observation vẫn giữ generation/UID guard và cleanup hiện có. Bookmark listener tiếp tục bị thay thế khi account đổi; callback cũ bị chặn bằng active UID.
- Coverage phase 5: lifecycle start idempotent, nhiều window cùng session, thay session nhanh, feature listener trì hoãn và chỉ start một lần; regression auth/device, settings sync, provider accounts và bookmarks: **64/64 test PASS**.
- Không launch/relaunch app; chưa kiểm tra tương tác nhiều window bằng runtime và chưa đo mức giảm RAM/cold start. Phần 5 đã commit tại `db2732e3`.

### Phần 6 — Cache và vòng đời còn lại (2026-09-28)

- Phase 5 đã commit tại `db2732e3` (`perf: coordinate cloud lifecycle once per app`).
- Thêm `BoundedMemoryCache` dùng access-order. Cache branch/reference giới hạn 32 entry, History giữ tối đa 3 snapshot branch/filter; entry cũ bị loại và request đang chạy bị hủy khi invalidate.
- Undo/redo giữ tối đa 50 action. Entry bị loại, redo bị thay thế và thao tác clear đều xóa file snapshot không còn được stack nào tham chiếu, nên dữ liệu phục vụ undo còn hiệu lực vẫn được giữ.
- Revision Browser hủy task và giải phóng tree/preview khi đóng. Repository AI hủy request/timer, pending operation và dữ liệu selector tạm khi window đóng.
- Các cache còn lại đã được audit và giữ nguyên khi đã có owner/giới hạn phù hợp: Welcome activity 20 entry, syntax-highlight preview 512 dòng không dài, revision tree 50.000 entry, PR payload dùng SQLite có giới hạn, diff/image/video theo vòng đời view, AI history lưu SQLite và chỉ conversation hiện tại resident.
- Coverage cache/History/undo/revision: **48/48 test PASS**. Regression Repository AI agent/remote lifecycle: **19/19 test PASS**. Build macOS: **PASS**; `git diff --check`: **PASS**.
- Không launch/relaunch app; chưa kiểm tra tương tác mở/đóng nhiều window bằng runtime và chưa đo mức giảm RAM/cold start. Phần 6 chưa commit.
