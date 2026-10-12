# QUY TRÌNH PASEO — bộ GODKIT (seatwork × mattpocock/skills, chạy trên Claude + Pi)

> Bản dịch của thiết kế 8 chẵng trong `../QUY-TRINH.md` (bản piggery) sang một room
> **supervisor → lead → peer(+lens)** sống ngay trong Paseo. Chassis = plugin `slp-seat`
> của seatwork; phương pháp = skills của Matt Pocock chạy trong session của bạn và các
> port (nét cốt lõi) chạy trong seat.

---

## 0. Ba luật vàng (không đổi so với QUY-TRINH)

1. **HITL chạy ở session của bạn. AFK chạy ở seat.** Kỹ năng nào cần bạn trả lời
   (grilling, triage, wayfinder, retro, pr) KHÔNG BAO GIỜ giao cho seat.
2. **Room không phải mặc định — room thì phải giành được.** 1 ticket nhỏ = 1 agent với
   mp-skills, không room. Room chỉ khi có song song thật hoặc cần review độc lập.
3. **Artifact là cầu nối context; mail chỉ chở con trỏ.** Mail bị cắt ở 4000 ký tự
   (seatwork) — brief dài là brief bị cắt phải luật, không chỉ là kỷ luật.

## 1. Ai giữ gì ở đâu

| Vai | Chạy trên | Giữ gì | KHÔNG được |
|---|---|---|---|
| **Bạn (session riêng)** | Claude Code + plugin mp-skills | Grill, spec, tickets, PR, retro | — |
| **HQ** | `claude-hq` | Portfolio các project, gửi chỉ thị xuống (dưới dạng "Owner") | Đụng việc trong project |
| **Supervisor** | `claude-supervisor` | Pin intent, chia workstream, heartbeat, `.slp/status.md` | Sửa code, accept kết quả |
| **Lead** | `claude-lead` | Kế hoạch workstream, briefs, **frontier**, **refinery (merge queue)**, chủ tịch review hai trục, đóng ticket | Đẻ worker vô hạn (policy cấm) |
| **Peer** | `claude-peer` / `pi-peer` | 1 ticket, 1 worktree, 1 outcome; TDD tại seam; challenge bằng evidence | Spawn ai; nhá nhem scope |
| **Lens** | `pi-lens` / `claude-lens` | 1 câu hỏi / 1 trục review, chỉ đọc, không biết nhau | Edit/Write (policy tắt) |

## 2. Tám chẵng

```
SESSION CỦA BẠN (HITL)                                    ROOM (AFK trên Paseo)
──────────────────────────                                ─────────────────────────────
1  /grill-with-docs   → GLOSSARY.md + ADR                 5  BUILD
2  /prototype | [Lens]-pair | /council (piggery)             Lead: slp-ticket-frontier
3  /to-spec           → chốt seam  (ready-for-agent)              → brief per ticket
4  /to-tickets        → vertical slices + blockers               Peer: slp-tdd (worktree)
       ── /clear ──                                              slp-refinery: merge queue
5–7 trả về session bạn qua report của Supervisor        6  REVIEW hai trục hai model
8  /retro + watcher stats + .slp/notebook.md           7  /pr (bạn quyết merge)
```

| Chẵng | Vai | Skill của godkit | mp-skills gốc | Cổng |
|---|---|---|---|---|
| 5 build — nạp | Lead | `slp-ticket-frontier` | `to-spec`+`to-tickets` artifacts | graph tường minh, không ticket open sau ACCEPT |
| 5 build — làm | Peer | `slp-tdd` | `tdd`, `implement` | red trước green tại seam đã chốt |
| 5 build — merge | Lead | `slp-refinery` | merger của `/implement-spec` | check xanh sau MỖI merge; đỏ → undo + REJECT |
| 5 build — bug | Peer | `slp-diagnose` | `diagnosing-bugs` ph1–2 | một lệnh red-capable tồn tại trước mọi giả thuyết |
| 6 review | Lens pair | `slp-two-axis-review` | `/code-review` | 2 báo cáo không merge/không rank; chốt sau 1 vòng fix |
| 7 ship | Bạn | — | `/pr` | Merge Danger + Evidence |
| 8 retro | Bạn | watcher stats + notebook | `/retro` | sửa MÔI TRƯỜNG: law / templates / checks |

## 3. Bảng định tuyến kỹ năng (HITL / AFK) — chỉ claude + pi

| Kỹ năng mp-skills | HITL/AFK | Chạy ở đâu |
|---|---|---|
| grilling / grill-with-docs / domain-modeling / to-spec / to-tickets / wayfinder / triage / teach / to-questionnaire / wait-what / wizard / improve-codebase-architecture | **HITL** | Session của bạn (plugin `mattpocock-skills`) |
| prototype / research / diagnosing-bugs | HITL chính, AFK phụ | Session, hoặc Peer seat (qua `slp-diagnose`; research qua `[Peer:research]` seatwork) |
| tdd / implement(1 ticket) | AFK | Peer seat → port bằng `slp-tdd` |
| implement-spec (orchestration) | AFK | **Thay bởi room**: Supervisor + Lead + `slp-ticket-frontier` + `slp-refinery` |
| code-review | AFK | Lens pair → port bằng `slp-two-axis-review` |
| retro / pr | HITL | Session của bạn |

Không port: `claude-handoff`, `claude-code` guards (misc/frozen), `scaffold-exercises`,
`migrate-to-shoehorn`. Piggery giữ vai gọi taskforce (`dual-lens`/`council`/`advisor`)
cho session của bạn BÊN NGOÀI room — hai hệ không cùng chạy trên một repo lúc một thời.

## 4. Những chỗ kit này CHỐT khác seatwork nguyên bản

| Vấn đề | seatwork nguyên bản | godkit |
|---|---|---|
| Merge song song | Lead hội nhập (sequential qua accept) | `slp-refinery`: queue + check từng merge + undo đỏ |
| Review mở rộng | lens theo angle, thường 1 | hai trục cố định + hai model family (`lens.pair` = pi + claude) |
| Nạp pipeline mp-skills | instruction tự do | `slp-ticket-frontier`: spec+ticket → briefs trường-đối-trường |
| Ticket lifecycle | không có tracker chuẩn | ticket đóng/nhãn superseded ngay khi ACCEPT (luật trong law) |
| Chuẩn kỹ thuật | role prompt + law ngắn | law trỏ vào `room/rules/godkit-engineering-standards.md` (mọi harness) |

## 5. Cài đặt

```bash
cd ~/workspace/my-paseo/seatwork        # clone seatwork (≥ commit Oct 2026)
git clone https://github.com/sting9k/seatwork.git   # nếu chưa có
cd ~/workspace/my-paseo/godkit
bash install.sh --claude-model <id-claude> --pi-model <id-pi>
#   --pi-model nên là model KHÔNG phải Anthropic để cross-family có nghĩa thật
#   mặc định: watcher = shadow; mở lên khi shadow bắt thật lỗi (retro quyết)
```

Kiểm chứng installer đã làm (4 kịch bản, đầu ra của `install.sh`):
chạy sạch → replace+backup; chạy 2 = idempotent 18 ok; user sửa tay → **không đụng**, cảnh
báo; `--force` → replace có backup. Lỗi placeholder sót lại / JSON hỏng → die trước khi
chạm seatwork installer.

## 6. Điều chưa giải (trung thực)

1. **Model của pi**: nếu pi đang chạy model Anthropic → cross-family thành hai mẫu cùng
   family. Là vẫn được: routing vẫn tách hai trục (cưỡng chế), chỉ mất độ độc lập model
   thật. Lâu dài: thêm OpenCode/Copilot provider cho tier cross-family.
1b. **dsh**: plugin `geoqiao/deepseek-harness` đưa dsh vào Paseo như **provider cá nhân**
   (`dsh --profile acp`) — tier 1, tự cài. Tier 2 **đã làm**: `install.sh --dsh-room` vá
   seatwork để `dsh-peer`/`dsh-lens` thành seat room thật — pair review trở thành
   **Claude lens ↔ DeepSeek lens** thật sự. Trạng thái: typecheck + 90/90 test plugin pass,
   installer 6 kịch bản 0 FAIL; **chưa chạy runtime thật** (cần daemon + dsh ≥ 0.2) — chi
   tiết, giới hạn và đường regenerate đọc ở **[DSH-PASEO.md](DSH-PASEO.md)**.
2. **Tracker GitHub trong room**: worker cần `gh` login trong runtime của nó; kit mặc định
   dùng local markdown `.scratch/<feature>/issues/NN-*.md` — chưa kiểm chứng gh.
3. **Chi phí**: room 3–5 peer + evals `claude -p` + watcher (budget 6 USD/tháng, key
   OpenRouter cho 4 luật model). Đo sau lần chạy đầu.
4. **License seatwork** chưa có → dùng cá nhân; chưa xin phép trước khi phân phối phần
   mã của nó.
5. **Retro khi có room**: nguồn sơ cấp = `.slp/notebook.md` + `.slp/status.md` + watcher
   stats (HQ gọi `slp_watch_stats`) — nguồn sơ cấp tốt hơn log thô của piggery nhưng vẫn
   cần 1–2 vòng thực tế để chốt thói quen.

## 7. Cây quyết định (đọc từ trên xuống, trúng thì dừng)

| Tình huống | Dùng |
|---|---|
| 1 ticket nhỏ, rõ ràng | Session riêng + mp-skills `/implement`. KHÔNG room. |
| Một quyết định khó | Session + taskforce `advisor`/`dual-lens` (piggery, ngoài room) — hoặc `[Lens]`-pair qua Supervisor |
| Nhiều ticket độc lập ở frontier | Room (5+6) — `slp-ticket-frontier` + `slp-refinery` |
| Việc mù mịt, quá lớn | `/wayfinder` trước, rồi mới `/to-spec`→`/to-tickets`→room |
| Bug khó | Peer seat + `slp-diagnose`; khi cần người click → BLOCKED về bạn |
| Bug/request ùn lại | `/triage` (HITL, session của bạn) |
| Multi-project | HQ + Supervisors (chỉ khi thực sự nhiều project song song) |