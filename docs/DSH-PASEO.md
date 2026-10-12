# DSH trong Paseo — plugin `geoqiao/deepseek-harness`, và GODKIT

Tài liệu phản hồi phát hiện của bạn: https://paseo.sh/plugins/geoqiao/deepseek-harness
(nguồn thật: github.com/geoqiao/paseo-stuff → `plugins/deepseek-harness`, MIT, cập nhật
2026-10-11, cài 23 lần, chạy qua SDK Paseo 0.11.2 trên macOS).

## 1. Plugin này là gì

- **Cài**: `paseo plugin add geoqiao/deepseek-harness` (kèm npm `paseo-deepseek-harness`,
  0.1.0-beta.10). Yêu cầu: Paseo ≥ 0.8, **dsh ≥ 0.1.5-rc.1** trên PATH của daemon
  (đã login + cấu hình sẵn), Node.js ≥ 22.19.0. Không cài dsh hộ, không đọc credential.
- **Cơ chế**: mỗi agent session = tiến trình con chạy **`dsh --profile acp`** (profile có thể
  đổi bằng env `DSH_PASEO_PROFILE`) dưới user của bạn, kế thừa môi trường của daemon.
  Model/effort lấy từ catalog mà `dsh` tự báo. Resume gọi dsh khôi phục context của chính nó.
- Plugin **chỉ là provider**: không có screen riêng; Paseo hiển thị conversation trong view
  agent thường.

## 2. Ba giới hạn cứng — và GODKIT xử lý từng cái như thế nào

| Giới hạn (từ OVERVIEW.md, đối chiếu source) | GODKIT xử lý |
|---|---|
| **Steering, plans, provider slash-commands, không hỗ trợ**; "Paseo's extra system prompt is not passed to dsh" | Room hoạt động đúng nhờ mail-đến-cuối-turn — seatwork **hold** mọi harness, không dùng steer; `mail.midTurn.dsh = "hold"` (block trong `delta`/patch). System prompt: plugin slp-seat vẫn mutate `agent.create` (dùng chung đường với claude/pi/opencode seats) |
| **Không sandbox / permission policy riêng** | `buildDsh()` (trong patch) dựng **DSH_HOME riêng mỗi seat**: share `.credentials.yaml` + `.anonymous-user-id` + `llm-deepseek/` bằng symlink (như claude seats share sign-in), **sessions/storages riêng**, và **KHÔNG chép `cordis.patch.yml` của bạn** — plugin layer cá nhân không load vào seat |
| **MCP: provider ACP nhận tool qua mcpServers injection của Paseo** | Plugin slp-seat đã tự inject `config.mcpServers.slp = { http, url+nonce, alwaysLoad }` cho MỌI seat (index.server.ts ~577) — seat dsh nhận room tools đúng đường này. Nếu dsh ACP từ chối mcpServers non-empty: đặt `policy.json → dsh.runtime.mcpServers = false` → seat dsh chạy nhưng không có room tool (chỉ dùng cho đọc/review ngoài room) |

Kết luận kiến trúc: seatwork hardcode `HARNESSES = ["claude","codex","pi","opencode"]`
(`plugin/server/seats.ts:8`); một provider `dsh-peer` **không phải seat của room** cho tới
khi vá. **GODKIT đã vá** — xem §4. Trước vá: dsh chỉ là provider cá nhân (bảng dưới vẫn đúng).

- **Hôm nay — dùng được ngay**: dsh = **provider cho session cá nhân của bạn trong Paseo**
  (việc lẻ, dò API, review một diff ở session riêng, kèm worktree workspace của Paseo), và
  khi piggery đang chạy: session dsh vẫn là "solo admittable" của farm nếu mở bằng
  `piggery setup dsh` như cũ. Room GODKIT giữ claude (HQ/Supervisor/Lead) + claude/pi
  (Peer/Lens).
- **Tier 2 — ĐÃ LÀM: `install.sh --dsh-room --dsh-model <id>`** (opt-in, **experimental**).
  Bản vá `dsh/seatwork-dsh.patch` (11 file, +123/−10 trên clone seatwork):

| File của seatwork | Patch sửa gì |
|---|---|
| `plugin/server/seats.ts` | `HARNESSES = [..., "dsh"]` |
| `plugin/server/paths.ts` | `DSH_HOME` const (env `DSH_TEST_HOME` cho test) |
| `plugin/server/policy.ts` | `DshRuntimePolicy {shareFiles, shareDirs, mcpServers}`; `RuntimePolicy.dsh?`; `mail.midTurn` + `dsh`; `loadPolicy` reads `dsh.runtime` (tùy chọn — không có → seat dsh bị từ chối, room claude/pi vẫn chạy) |
| `plugin/server/runtimes.ts` | `buildDsh()` (share sign-in bằng symlink, NO cordis patch, sessions riêng) + `build()` case + `envFor` case `{DSH_HOME: dir}` + `describeIsolation` |
| `plugin/test/support/room.ts` | `DSH_TEST_HOME` env, `USER_DSH` export, `midTurn.dsh: "hold"` |
| `plugin/test/runtime-dsh.test.ts` | **3 test mới** (share credentials/symlink; llm-deepseek + envFor; thiếu dsh.runtime → refuse có nêu chỗ sửa) |
| `paseo/policy.json` | Block `"dsh": {"runtime": {...}}` + `mail.midTurn.dsh = "hold"` |
| `room/harness/dsh-harness.md` | Sheet: tool qua MCP injection, profile `acp`, modes không có |
| `tools/choices.py` | `HARNESSES` + `"dsh"`; `CATALOG_PROVIDER["dsh"] = "deepseek-harness"` (catalog từ provider runtime-discovery) |
| `tools/gen-snippet.py` | LABEL/ISOLATION dsh; provider entry dsh = **`extends: "acp"` + `command: ["dsh","--profile","acp"]` + env `DSH_HOME` = runtime của seat** + `options.supportsMcpServers:false` khi policy tắt |
| `install.sh` | jq regex nhận diện provider của room thêm `dsh` |
| `paseo/policy.json` (claude deny) | `Bash(dsh:*)` ở cả 5 role — seat Claude không mở được dsh lồng. **pi không có deny tương đương**: seat pi chỉ bị chặn bằng prompt |

  **Đã kiểm chứng tĩnh** (trên máy này): `git apply --check` sạch trên clone pristine;
  `npm run typecheck` sạch; **`npm test` = 90/90 pass** (87 test seatwork + 3 test dsh; sau khi kit đặt `models.json` của nó thì `onboard.test` đỏ có chủ đích — installer chỉ chạy `runtime-dsh.test.ts` + typecheck);
  godkit installer: 6 kịch bản (default fresh/idempotent/user-edit/drifted-clone die;
  dsh-room fresh/idempotent) đều 0 FAIL. **Chưa kiểm chứng runtime thật** (cần daemon
  Paseo chạy + dsh ≥ 0.2 thật): hành vi resume/abort qua ACP, và seat dsh có nhận đúng
  mcpServers injection hay không — kịch bản "dsh ACP từ chối mcpServers" đã có lối thoát
  trong installer (mcpServers: false) và được đề trong Next-steps.

  **Regenerate patch** khi seatwork clone nhảy phiên bản: chạy lại các bước §4 trên
  clone mới (HARNESSES/paths/policy/runtimes sheet gen-snippet/choices), rồi
  `git diff > godkit/dsh/seatwork-dsh.patch`; `install.sh --dsh-room` sẽ nói rõ khi patch
  không apply nữa.

## 3. Cập nhật cây quyết định

| Tình huống | Dùng |
|---|---|
| Việc lẻ mà bạn muốn làm bằng dsh | Session cá nhân của bạn trong Paseo qua provider `DeepSeek Harness` (tier 1, tự cài) — KHÔNG room, KHÔNG seat |
| dsh vào room làm Peer cross-family / Lens | `install.sh --dsh-room --dsh-model <id>` (tier 2, experimental) — room được pair **Claude lens ↔ DeepSeek lens** thật |
| dsh tham gia taskforce độc lập (dual-lens) | piggery (ngoài room): `dsh web` solo → spawn taskforce từ đó — đã kiểm chứng cùng extension piggery v0.9.1 |