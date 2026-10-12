# 🐗 GODKIT — bộ engineering pipeline cho Paseo
### piggery-tư duy (gate + mail + worktree) × seatwork-chassis × mattpocock/skills

Một room **Supervisor → Lead → Peer (+Lens, +HQ)** sống ngay trong Paseo, chạy trên
**Claude Code + Pi** (mỗi vai một seat provider cách ly), nạp nguyên tắc và phương pháp
kỹ thuật của [mattpocock/skills](https://github.com/mattpocock/skills), và giữ lại toàn bộ
kinh nghiệm cưỡng chế của [sting8k/piggery](https://github.com/sting8k/piggery) mà bộ
`workflow/` cũ đã kiểm chứng.

```
   BẠN (Claude Code + mp-skills, HITL)          ROOM TRONG PASEO (AFK)
   1 /grill-with-docs → GLOSSARY + ADR          5 BUILD   Lead slp-ticket-frontier
   3 /to-spec        → seam                     →   Peer slp-tdd (worktree mỗi ticket)
   4 /to-tickets     → vertical slices              Lead slp-refinery (merge queue)
   7 /pr · 8 /retro   ← report+evidence ←←←←    6 REVIEW  lens pair · slp-two-axis-review
```

## Lõi của bộ (5 skill + 1 thanh chuẩn + 1 luật)

| File | Vai |
|---|---|
| `delta/skills/lead/slp-ticket-frontier/SKILL.md` | Nạp spec+tickets (artifact của `/to-spec`+`/to-tickets`) → briefs; ticket `accepted` khi ACCEPT, **chỉ đóng khi merge xanh** (refinery) |
| `delta/skills/lead/slp-refinery/SKILL.md` | **Merge queue thật**: 1 integration branch, check sau mỗi merge, merge `--no-commit` → check → xanh mới commit; đỏ → abort + REJECT (không bao giờ commit đỏ, không tự vá) |
| `delta/skills/lead/slp-two-axis-review/SKILL.md` | Review đóng bài: **2 lens seat · 2 model family · 2 trục** (Standards/Spec), không merge kết quả |
| `delta/skills/peer/slp-tdd/SKILL.md` | Port `tdd`: red→green tại seam đã chốt; 3 anti-pattern |
| `delta/skills/peer/slp-diagnose/SKILL.md` | Port `diagnosing-bugs`: **loop red-capable trước mọi giả thuyết** |
| `delta/rules/godkit-engineering-standards.md` | Thanh chuẩn cho mọi seat (law trỏ vào; repo thắng khi nghiêm hơn) |
| `delta/seats.yml` + `delta/models.json` | Room chạy **claude + pi**; peer tier `cross-family` + lens pair dùng pi family. **dsh**: [docs/DSH-PASEO.md](docs/DSH-PASEO.md) + `dsh/seatwork-dsh.patch` — tier 1 cài provider cá nhân `geoqiao/deepseek-harness` (mặc định), tier 2 `--dsh-room` biến `dsh-peer`/`dsh-lens` thành seat room thật (DSH_HOME cách ly, không user cordis patch) |

## Cài đặt (một máy có paseo ≥ 0.10.3, claude, pi)

```bash
git clone https://github.com/sting9k/seatwork.git ~/workspace/my-paseo/seatwork
bash ~/workspace/my-paseo/godkit/install.sh \
       --claude-model <id-claude> --pi-model <id-pi>
# dsh: tier 1 tự cài provider cá nhân (dsh có trên PATH là chạy);
# tier 2 — dsh làm seat trong room (cross-family thật, DeepSeek ↔ Claude):
#   bash install.sh --dsh-room --dsh-model <id-dsh>      # experimental — xem docs/DSH-PASEO.md
# mặc định watcher=shadow (chỉ ghi log). Mở --watcher on sau khi retro thấy nó bắt thật lỗi.
```

`install.sh` làm theo 5 pha: **kiểm tra → staging (chỉ đọc) → ghi có journal → side-effect → verify**.
- Mọi kiểm tra (model id, render `models.json`/`<ROOM_DIR>`, trạng thái patch dsh, ai sở hữu file
  nào) xong **trước khi ghi một byte**; lỗi ở pha ghi → **rollback** mọi file đã chạm (và gỡ patch).
- Quyền sở hữu file theo **manifest sha256** (`slp-room/.godkit-manifest.tsv`): file được thay khi
  nó đúng bản kit ghi lần trước, hoặc đúng bản upstream seatwork đã commit; khác đi là **của bạn**
  → không đụng (cảnh báo), trừ khi `--force`. Không đoán từ `git status` nữa. Cài từ bản kit cũ
  (chưa có manifest) cần một lần `--force` để nhận lại quyền.
- Backup ở `slp-room/.godkit-backup/<stamp>/` (ngoài `room/`, không bị rsync lên máy). Patch dsh
  được xác nhận bằng `git apply --check` / `-R --check`, không bằng chuỗi `"dsh"`.
- Chạy lại không reset watcher/HQ của máy (chỉ lần cài đầu hoặc khi bạn truyền cờ).
- Dùng `--skip-seatwork-install` khi chỉ muốn đặt file, `--skip-checks` cho CI.
Kiểm chứng (sandbox, `--skip-checks`): sạch / lặp lại / đổi model id / đổi variant ↔ `--dsh-room` /
user-edit đã commit / git worktree / model id hỏng / patch dở / rollback giữa chừng.

## Dùng hằng ngày

- Session của bạn: `/setup-matt-pocock-skills` (1 lần/repo) → `/grill-with-docs` →
  `/to-spec` → `/to-tickets` → **`/clear`** → giao room.
- Room: mở agent profile **Supervisor** trong project → *"Spec and tickets are at
  `.scratch/<feature>/issues/` — run the pipeline. Integration branch: integration/<feature> from
  <base>; the Lead may merge to it locally (no push, no deploy); the base branch never moves."*
  (Tên branch + quyền merge phải nằm trong instruction hoặc law — refinery dừng ở `DECISION_NEEDED` nếu thiếu.)
- Xoay phòng: paseo app (agents, permission, workspaces) · `.slp/status.md và notebook.md` ·
  HQ "watcher stats".
- Kết thúc: `/pr` và `/retro` ở session của bạn; retro sửa **môi trường** (law, skill,
  watcher rule), không sửa code của room.

## Tài liệu

- **[docs/QUY-TRINH-PASEO.md](docs/QUY-TRINH-PASEO.md)** — tài liệu chính: 8 chẵng, vai,
  bảng định tuyến HITL/AFK, cây quyết định, điều chưa giải.
- [evals/README-godkit.md](evals/README-godkit.md) — 4 case kiểm hành vi quan trọng nhất + `--selftest` (14 transcript tốt/xấu kiểm chính các grader).
- [docs/REVIEW-2026-10-11.md](docs/REVIEW-2026-10-11.md) — review độc lập toàn bộ kit (+ trạng thái xử lý
  ở đầu file) và [docs/REVIEW-2026-10-12.md](docs/REVIEW-2026-10-12.md) — dual-lens review (Opus 5.5 ‖ GPT 6.1 Sol)
  cùng thứ tự đã sửa.
- Nguồn: `~/Downloads/god/QUY-TRINH.md` (thiết kế 8 chẵng gốc), `piggery-report.md`
  (kiến trúc piggery chi tiết), clone `piggery`, `mp-skills`, `seatwork`.
- Phân phối: [LICENSE](LICENSE) (MIT cho nội dung gốc) + [NOTICE.md](NOTICE.md) — seatwork
  **không** nằm trong repo này (chưa có license; tự clone theo hướng dẫn cài đặt).

## Nguyên tắc (giữ nguyên từ QUY-TRINH)

1. **HITL ở session của bạn; AFK ở seat.**
2. **Room phải giành được** — 1 ticket nhỏ = 1 agent, không room.
3. **Artifact là hợp đồng; mail chỉ chở con trỏ** (mail bị cắt ở 4000 ký tự).
4. **Cưỡng chế cái cơ học bằng code** (policy.json routes/tools/runtimes), **khuyên cái
   phán đoán bằng prompt** (skills, law).
5. **Retro sửa môi trường** — watcher + notebook + evals là bộ ba tích luỹ của bộ này.