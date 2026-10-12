#!/usr/bin/env bash
# GODKIT installer: turns a seatwork clone into the godkit pipeline room.
#
#   claude + pi + dsh · spec → tickets → build → two-axis review → ship → retro
#
# Shape (idempotent; all-or-nothing on the files it touches):
#   A. checks (read-only): paseo, claude, pi, dsh, jq, git, python3+PyYAML, a seatwork clone
#   B. stage (read-only): validate model ids, render models.json, paseo/profiles.json and the <ROOM_DIR> pointers into
#      a temp dir, work out for every target whether it is the kit's own earlier copy, seatwork's
#      original, or yours, and (--dsh-room) whether dsh/seatwork-dsh.patch applies. Any failure
#      here dies before one byte is written.
#   C. write (journaled): the dsh patch (tier 2, opt-in), then the kit's files, then the marked
#      law/harness blocks. If anything fails, every file is restored and the patch reversed.
#      Backups of replaced files go to <clone>/slp-room/.godkit-backup/<stamp>/ (outside room/,
#      so seatwork's rsync never ships them).
#   D. side effects that cannot be rolled back: dsh tier 1 (paseo plugin add), seatwork's own
#      ./install.sh (providers, plugin, daemon reload).
#   E. verify and print the next steps.
#
# Who owns a file (decides whether it is replaced): <clone>/slp-room/.godkit-manifest.tsv records
# the sha256 of every file the kit wrote. A file is replaced when it equals that record (the
# kit's own copy, untouched) or equals seatwork's committed upstream copy; any other difference
# is treated as yours and left alone. --force replaces anyway (with a backup). seats.yml and
# models.json travel as a pair: if one is yours, both are left alone.
#
# Flags:
#   --seatwork-dir PATH      (default: ../seatwork next to this script, or $SEATWORK_DIR)
#   --claude-model ID        (default: $GODKIT_CLAUDE_MODEL, else asks once)
#   --pi-model ID            (default: $GODKIT_PI_MODEL, else asks once)
#   --dsh-model ID           (default: $GODKIT_DSH_MODEL, else asks once; --dsh-room only)
#   --dsh-room               patch seatwork so dsh holds room seats (tier 2, experimental)
#   --no-dsh-personal        skip tier 1 (do not add the deepseek-harness Paseo plugin)
#   --watcher shadow|on|off  first install: default shadow (it logs, it mails nobody). A re-run
#                            without the flag leaves the machine's choice alone.
#   --force                  replace files you edited (backed up); it does NOT re-apply the dsh patch
#   --skip-checks            advanced use/CI: skip the paseo/claude/pi/dsh checks
#   --skip-dsh-tests         with --dsh-room: do not typecheck+test the patched plugin
#   --keep-daemon-features   seatwork installs with --no-daemon-policy: the room's required
#                            switches (daemon.mcp.enabled + injectIntoAgents + pluginsEnabled) still
#                            apply, so your browser tools, terminal hooks, dictation/voice mode and
#                            Paseo's bundled-skills selection stay exactly as they are now
#   --skip-seatwork-install  advanced use: only place files, don't run seatwork's installer
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGER="$SRC/tools/stage.py"
WATCHER=""; SW_DIR=""; CLAUDE_MODEL=""; PI_MODEL=""; DSH_MODEL=""; FORCE=0; RUN_SEATWORK=1
DSH_PERSONAL=1; DSH_ROOM=0; DSH_TESTS=1; KEEP_FEATURES=0; SKIP_CHECKS=0
# seatwork commit the kit and its dsh patch were built and verified against
UPSTREAM_PIN="6528777"

ok=0; warn=0; left_alone=0
say()     { printf '  %s\n' "$*"; }
good()    { ok=$((ok+1));  printf '  ok    %s\n' "$*"; }
warning() { warn=$((warn+1)); printf '  warn  %s\n' "$*"; }
die()     { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
section() { printf '\n%s\n' "$*"; }

while [ $# -gt 0 ]; do case "$1" in
  --seatwork-dir) [ $# -ge 2 ] || die "$1 needs a value"; SW_DIR="$2"; shift 2 ;;
  --claude-model) [ $# -ge 2 ] || die "$1 needs a value"; CLAUDE_MODEL="$2"; shift 2 ;;
  --pi-model)     [ $# -ge 2 ] || die "$1 needs a value"; PI_MODEL="$2"; shift 2 ;;
  --dsh-model)    [ $# -ge 2 ] || die "$1 needs a value"; DSH_MODEL="$2"; shift 2 ;;
  --dsh-room)     DSH_ROOM=1; shift ;;
  --dsh-personal) DSH_PERSONAL=1; shift ;;
  --no-dsh-personal) DSH_PERSONAL=0; shift ;;
  --skip-dsh-tests) DSH_TESTS=0; shift ;;
  --keep-daemon-features) KEEP_FEATURES=1; shift ;;
  --watcher)      [ $# -ge 2 ] || die "$1 needs a value"; WATCHER="$2"; shift 2 ;;
  --force)        FORCE=1; shift ;;
  --skip-checks)  SKIP_CHECKS=1; shift ;;
  --skip-seatwork-install) RUN_SEATWORK=0; shift ;;
  *) die "unknown flag: $1" ;;
esac; done

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/godkit-install.XXXXXX")"
JOURNAL="$STAGE/journal"; : > "$JOURNAL"
ARMED=0; STAMP="$(date +%Y%m%d-%H%M%S)-$$"

rollback() {
  printf '\n  ROLLBACK  restoring every file this run touched\n' >&2
  awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$JOURNAL" | while IFS="$(printf '\t')" read -r kind a b; do
    case "$kind" in
      restore) cp -p "$b" "$a" 2>/dev/null || { : > "$STAGE/rollback.failed"; printf '  could not restore %s (copy is at %s)\n' "$a" "$b" >&2; } ;;
      remove)  rm -f "$a" ;;
      unpatch) ( cd "$SW_DIR" && git apply -R "$a" ) 2>/dev/null || { : > "$STAGE/rollback.failed"; printf '  could not reverse the dsh patch: git -C %s apply -R %s\n' "$SW_DIR" "$a" >&2; } ;;
    esac
  done
  [ -e "$STAGE/rollback.failed" ] || rm -rf "$BK_DIR"
}
cleanup() {
  local rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ] && [ "$ARMED" = 1 ]; then rollback; fi
  rm -rf "$STAGE"
  exit "$rc"
}
trap cleanup EXIT

# ================================================================ A. checks (read-only)
section "Checking what is installed"

if [ -n "$WATCHER" ]; then
  [ "$WATCHER" = off ] || [ "$WATCHER" = shadow ] || [ "$WATCHER" = on ] \
    || die "--watcher must be off, shadow or on"
fi
for bin in python3 git; do command -v "$bin" >/dev/null 2>&1 || die "$bin missing"; done
command -v jq >/dev/null 2>&1 || die "jq missing"
python3 -c "import yaml" >/dev/null 2>&1 || die "python3 with PyYAML missing"

DSH=0
if [ "$SKIP_CHECKS" = 1 ]; then
  warning "checks skipped (--skip-checks): placing files only"
else
  command -v paseo >/dev/null 2>&1 || die "paseo is not on PATH. Install it: https://paseo.sh"
  good "paseo: $(paseo --version 2>/dev/null || echo 'version unknown') — the room needs >= 0.10.3"
  CLAUDE=0
  command -v claude >/dev/null 2>&1 && CLAUDE=1 || warning "claude not on PATH (HQ/Supervisor/Lead run on claude seats)"
  command -v pi     >/dev/null 2>&1 || warning "pi not on PATH (the lens pool loses one family)"
  command -v dsh    >/dev/null 2>&1 && DSH=1    || warning "dsh not on PATH (no DeepSeek tier; --dsh-room needs it)"
  [ "$CLAUDE" = 1 ] || die "claude is required (claude auth login once)"
  if [ "$DSH" = 1 ] && [ "$DSH_ROOM" = 1 ]; then
    # the floor is 0.2 (prereleases of 0.2.0 count: rc.1 is the version the ACP contracts were verified on)
    dshv="$( { dsh --version 2>/dev/null || true; } | head -1 | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?).*/\1/p')"
    dmaj="$(printf '%s' "$dshv" | cut -d. -f1)"; dmin="$(printf '%s' "$dshv" | cut -d. -f2)"
    if [ -z "$dshv" ]; then warning "could not read 'dsh --version'; the room's ACP contracts were verified on dsh >= 0.2.0-rc.1"
    elif [ "${dmaj:-0}" -gt 0 ] || [ "${dmin:-0}" -ge 2 ]; then good "dsh: $dshv"
    else warning "dsh $dshv is below 0.2.0-rc.1, the version the room's ACP contracts were verified on"; fi
  fi
fi

[ -n "$SW_DIR" ] || SW_DIR="${SEATWORK_DIR:-$SRC/../seatwork}"
[ -d "$SW_DIR" ] || die "no seatwork clone at $SW_DIR (git clone https://github.com/sting9k/seatwork.git)"
SW_DIR="$(cd "$SW_DIR" && pwd)"
[ -f "$SW_DIR/slp-room/install.sh" ] || die "no seatwork clone at $SW_DIR (git clone https://github.com/sting9k/seatwork.git)"
SW_ROOM="$SW_DIR/slp-room"
IS_GIT=0; git -C "$SW_DIR" rev-parse --git-dir >/dev/null 2>&1 && IS_GIT=1
good "seatwork clone: $SW_DIR$([ "$IS_GIT" = 1 ] || echo ' (not a git checkout: its files cannot be recognised as seatwork originals)')"

ROOM_HOME="${SLP_ROOM_HOME:-$HOME/.config/slp-room}"
ROOM_DIR_ABS="$ROOM_HOME/room"   # where seatwork's installer puts room/; seats are never shown this path, so it is rendered into the pointers

# ================================================================ B. stage (read-only)
section "Staging (nothing is written until every check below passes)"

# --- model ids
[ -n "$CLAUDE_MODEL" ] || CLAUDE_MODEL="${GODKIT_CLAUDE_MODEL:-}"
[ -n "$PI_MODEL" ]     || PI_MODEL="${GODKIT_PI_MODEL:-}"
[ -n "$DSH_MODEL" ]    || DSH_MODEL="${GODKIT_DSH_MODEL:-}"
if [ -z "$CLAUDE_MODEL" ] || [ -z "$PI_MODEL" ] || { [ "$DSH_ROOM" = 1 ] && [ -z "$DSH_MODEL" ]; }; then
  printf '\n  Model ids the room will pin (they must exist in each harness catalog).\n'
  printf '  The lens pair is meant to be TWO families, and dsh-peer carries the cross-family tier.\n'
fi
ask() { # ask <var> <prompt>
  local v
  while [ -z "${!1}" ]; do printf '  %s' "$2"; read -r v || die "no input for $2— pass the model id as a flag or GODKIT_*_MODEL"; printf -v "$1" '%s' "$v"; done
}
ask CLAUDE_MODEL "claude model id (e.g. claude-opus-4-6): "
ask PI_MODEL     "pi model id (lens pair + cross-family peer; not an Anthropic model, or the pair is one family): "
[ "$DSH_ROOM" = 0 ] || ask DSH_MODEL "dsh model id (cross-family tier + lens pair; as dsh reports it): "
for pair in "claude:$CLAUDE_MODEL" "pi:$PI_MODEL" "dsh:${DSH_MODEL:-x}"; do
  printf '%s' "${pair#*:}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:@/+-]*$' \
    || die "${pair%%:*} model id '${pair#*:}' has characters outside [A-Za-z0-9._:@/+-] (quotes, spaces, & | \\ would corrupt models.json)"
done
if [ "$DSH_ROOM" = 1 ]; then good "models: claude=$CLAUDE_MODEL  pi=$PI_MODEL  dsh=$DSH_MODEL"
else good "models: claude=$CLAUDE_MODEL  pi=$PI_MODEL"; fi

# --- the kit's variant and the rendered files
SEATS_SRC="seats.yml"; MODELS_SRC="models.json"
if [ "$DSH_ROOM" = 1 ]; then SEATS_SRC="seats.dsh.yml"; MODELS_SRC="models.dsh.json"; fi
KIT_FILES=("delta/$SEATS_SRC" "delta/$MODELS_SRC" "delta/law/godkit-law-additions.md" "delta/law/godkit-harness-pointer.md" \
  "delta/rules/godkit-engineering-standards.md" \
  "delta/skills/lead/slp-ticket-frontier/SKILL.md" "delta/skills/lead/slp-refinery/SKILL.md" \
  "delta/skills/lead/slp-two-axis-review/SKILL.md" "delta/skills/lead/slp-two-axis-review/references/two-axis-formats.md" \
  "delta/skills/peer/slp-tdd/SKILL.md" "delta/skills/peer/slp-diagnose/SKILL.md" "tools/stage.py")
for f in "${KIT_FILES[@]}"; do [ -f "$SRC/$f" ] || die "missing kit file: $f — this is a kit bug"; done

RENDERED_MODELS="$STAGE/models.json"
mdl_args=("_CLAUDE_MODEL_=$CLAUDE_MODEL" "_PI_MODEL_=$PI_MODEL")
[ "$DSH_ROOM" = 0 ] || mdl_args+=("_DSH_MODEL_=$DSH_MODEL")
python3 "$STAGER" render "$SRC/delta/$MODELS_SRC" "$RENDERED_MODELS" "${mdl_args[@]}" || die "could not render models.json"
jq -e . "$RENDERED_MODELS" >/dev/null 2>&1 || die "rendered models.json is not valid JSON — this is a kit bug"
python3 "$STAGER" render "$SRC/delta/law/godkit-law-additions.md" "$STAGE/law.block" "<ROOM_DIR>=$ROOM_DIR_ABS" || die "could not render the law block"
python3 "$STAGER" render "$SRC/delta/law/godkit-harness-pointer.md" "$STAGE/pointer.block" "<ROOM_DIR>=$ROOM_DIR_ABS" || die "could not render the harness pointer"
good "rendered models.json and the rule-file pointers (room dir: $ROOM_DIR_ABS)"

# --- who owns what is there now
MANIFEST="$SW_ROOM/.godkit-manifest.tsv"
manifest_sha() { [ -f "$MANIFEST" ] && awk -F'\t' -v p="$1" '$1==p{print $2}' "$MANIFEST" | tail -1 || true; }
file_sha() { python3 "$STAGER" sha "$1"; }
UPSTREAM_REFS="origin/HEAD origin/main origin/master ${GODKIT_UPSTREAM_REF:-} $UPSTREAM_PIN"
upstream_shas() { # upstream_shas <rel under slp-room>: sha256 of that file at each known upstream ref
  [ "$IS_GIT" = 1 ] || return 0
  local ref
  for ref in $UPSTREAM_REFS; do
    git -C "$SW_DIR" cat-file -e "$ref:./slp-room/$1" 2>/dev/null || continue
    git -C "$SW_DIR" show "$ref:./slp-room/$1" 2>/dev/null | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  done
}
classify() { # classify <rel under slp-room> <staged source> -> create|current|replace-kit|replace-upstream|replace-force|skip-user
  local d="$SW_ROOM/$1" cur ups
  [ -e "$d" ] || { echo create; return; }
  cmp -s "$2" "$d" && { echo current; return; }
  [ "$FORCE" = 0 ] || { echo replace-force; return; }
  cur="$(file_sha "$d")"
  [ "$(manifest_sha "$1")" = "$cur" ] && { echo replace-kit; return; }
  ups="$(upstream_shas "$1")"
  case "$(printf '\n%s\n' "$ups")" in *"$(printf '\n%s\n' "$cur")"*) echo replace-upstream; return ;; esac
  echo skip-user
}

# Paseo's agent profiles (the app's way into the room) name a model per provider: render yours, not the id seatwork's author had
PROFILES_SRC="$SW_ROOM/paseo/profiles.json"
[ -f "$PROFILES_SRC" ] || die "expected file missing: $PROFILES_SRC (is this a seatwork clone?)"
RENDERED_PROFILES="$STAGE/profiles.json"
jq --arg c "$CLAUDE_MODEL" --arg p "$PI_MODEL" --arg d "${DSH_MODEL:-}" \
  'map(if (.provider|startswith("claude-")) then .model=$c elif (.provider|startswith("pi-")) then .model=$p elif ((.provider|startswith("dsh-")) and $d != "") then .model=$d else . end)' \
  "$PROFILES_SRC" > "$RENDERED_PROFILES" || die "could not render paseo/profiles.json"

PLAN="$STAGE/plan.tsv"; : > "$PLAN"   # action <TAB> rel under slp-room <TAB> source file
plan() { printf '%s\t%s\t%s\n' "$(classify "$1" "$2")" "$1" "$2" >> "$PLAN"; }
plan "paseo/seats.yml"       "$SRC/delta/$SEATS_SRC"
plan "room/models.json"      "$RENDERED_MODELS"
plan "paseo/profiles.json"   "$RENDERED_PROFILES"
for s in skills/lead/slp-ticket-frontier/SKILL.md skills/lead/slp-refinery/SKILL.md \
         skills/lead/slp-two-axis-review/SKILL.md skills/lead/slp-two-axis-review/references/two-axis-formats.md \
         skills/peer/slp-tdd/SKILL.md skills/peer/slp-diagnose/SKILL.md; do
  plan "room/$s" "$SRC/delta/$s"
done
plan "room/rules/godkit-engineering-standards.md" "$SRC/delta/rules/godkit-engineering-standards.md"

# seats.yml and models.json are one decision: the installer refuses a models.json that names a seat seats.yml lacks
act_of() { awk -F'\t' -v r="$1" '$2==r{print $1}' "$PLAN"; }
set_act() { awk -F'\t' -v OFS='\t' -v r="$1" -v a="$2" '$2==r{$1=a}1' "$PLAN" > "$PLAN.new" && mv "$PLAN.new" "$PLAN"; }
sa="$(act_of paseo/seats.yml)"; ma="$(act_of room/models.json)"
if [ "$sa" = skip-user ] && [ "$ma" != skip-user ] && [ "$ma" != current ]; then set_act room/models.json skip-pair; fi
if [ "$ma" = skip-user ] && [ "$sa" != skip-user ] && [ "$sa" != current ]; then set_act paseo/seats.yml skip-pair; fi

# the marked blocks go into seatwork files; each must be there before anything is written
BLOCK_TARGETS="room/skills/supervisor/slp-project-law/references/project-law.md=law room/harness/claude-harness.md=pointer room/harness/pi-harness.md=pointer"
for t in $BLOCK_TARGETS; do
  [ -f "$SW_ROOM/${t%=*}" ] || die "expected file missing: $SW_ROOM/${t%=*} (is this a seatwork clone?)"
  python3 "$STAGER" block "$SW_ROOM/${t%=*}" "$STAGE/${t#*=}.block" "$STAGE/block.check" || die "cannot patch ${t%=*}"
done

# --- the dsh patch: fresh, applied, or neither (never guessed from a string)
PATCH="$SRC/dsh/seatwork-dsh.patch"; PATCH_STATE=none
DSH_SHEET_EXCLUDE="--exclude=slp-room/room/harness/dsh-harness.md"   # the kit appends its pointer to this new file
patch_state() {
  if ( cd "$SW_DIR" && git apply --check "$PATCH" ) >/dev/null 2>&1; then echo fresh
  elif ( cd "$SW_DIR" && git apply -R --check "$DSH_SHEET_EXCLUDE" "$PATCH" ) >/dev/null 2>&1 && [ -f "$SW_ROOM/room/harness/dsh-harness.md" ]; then echo applied
  else echo neither; fi
}
if [ "$DSH_ROOM" = 1 ]; then
  [ -f "$PATCH" ] || die "dsh patch missing: $PATCH — this is a kit bug"
  [ "$IS_GIT" = 1 ] || die "--dsh-room applies the patch through git; $SW_DIR is not a git checkout"
  PATCH_STATE="$(patch_state)"
  case "$PATCH_STATE" in
    fresh)   good "dsh patch applies cleanly" ;;
    applied) good "dsh patch: already fully applied" ;;
    *) die "the dsh patch neither applies nor is fully applied (the seatwork clone has drifted or holds half of it). Nothing was changed. Re-clone seatwork, or regenerate the patch (docs/DSH-PASEO.md, 'Regenerate patch')." ;;
  esac
fi

while IFS="$(printf '\t')" read -r act rel _; do
  case "$act" in
    skip-user) left_alone=$((left_alone+1)); warning "$rel is neither the kit's last copy nor seatwork's original (yours, or from an older kit); it will be left alone — --force replaces it with a backup" ;;
    skip-pair) left_alone=$((left_alone+1)); warning "$rel will be left alone because its partner (seats.yml ↔ models.json) is yours" ;;
  esac
done < "$PLAN"
good "staged: $(wc -l < "$PLAN" | tr -d ' ') files planned, patch state: $PATCH_STATE"

# ================================================================ C. write (journaled)
section "Writing godkit files"
ARMED=1
BK_DIR="$SW_ROOM/.godkit-backup/$STAMP"
journal_before() { # journal_before <abs path>: remember how to undo a write to it
  local rel="${1#$SW_DIR/}"
  if [ -e "$1" ]; then
    mkdir -p "$BK_DIR/$(dirname "$rel")"; cp -p "$1" "$BK_DIR/$rel"
    printf 'restore\t%s\t%s\n' "$1" "$BK_DIR/$rel" >> "$JOURNAL"
  else printf 'remove\t%s\n' "$1" >> "$JOURNAL"; fi
}

# --- dsh patch (tier 2) before the kit's files: its plugin test reads upstream's own room files
if [ "$DSH_ROOM" = 1 ]; then
  section "dsh (tier 2): seatwork patched so dsh holds room seats (experimental)"
  if [ "$PATCH_STATE" = fresh ]; then
    ( cd "$SW_DIR" && git apply "$PATCH" ) || die "git apply failed unexpectedly after --check passed"
    printf 'unpatch\t%s\n' "$PATCH" >> "$JOURNAL"
    good "dsh patch applied (uncommitted in the clone: 'git -C $SW_DIR diff' reviews it, 'git -C $SW_DIR apply -R $PATCH' reverts it)"
  fi
  if [ "$DSH_TESTS" = 1 ] && [ "$SKIP_CHECKS" = 0 ]; then
    # the full suite is not run here: onboard.test expects upstream's room/models.json, which the kit replaces by design
    if ( cd "$SW_ROOM/plugin" && npm install --no-audit --no-fund >/dev/null 2>&1 && npm run typecheck >/dev/null 2>&1 \
         && node --require ./test/register.cjs --test test/runtime-dsh.test.ts >/dev/null 2>&1 ); then
      good "patched plugin: npm install + typecheck + runtime-dsh tests pass"
    else
      warning "the patched plugin did not verify locally (npm/typecheck/runtime-dsh) — see $SW_ROOM/plugin; the room keeps working, dsh seats may not"
    fi
  fi
fi

# --- the kit's files
NEW_MANIFEST="$STAGE/manifest.new"
{ [ -f "$MANIFEST" ] && cat "$MANIFEST" || true; } > "$NEW_MANIFEST"
record() { # record <rel>: the file now holds the kit's content
  awk -F'\t' -v r="$1" '$1!=r' "$NEW_MANIFEST" > "$NEW_MANIFEST.t"; mv "$NEW_MANIFEST.t" "$NEW_MANIFEST"
  printf '%s\t%s\n' "$1" "$(file_sha "$SW_ROOM/$1")" >> "$NEW_MANIFEST"
}
while IFS="$(printf '\t')" read -r act rel srcf; do
  d="$SW_ROOM/$rel"
  case "$act" in
    create|replace-kit|replace-upstream|replace-force)
      journal_before "$d"; mkdir -p "$(dirname "$d")"; cp "$srcf" "$d"; record "$rel"
      case "$act" in
        create) good "$rel" ;;
        replace-kit) good "$rel updated (the kit's own earlier copy; backup kept)" ;;
        replace-upstream) good "$rel replaced (was seatwork's original; backup kept)" ;;
        replace-force) good "$rel replaced (--force; backup kept)" ;;
      esac ;;
    current) record "$rel"; good "$rel already current" ;;
    skip-user|skip-pair) : ;;
  esac
done < "$PLAN"

# --- marked blocks (law template, harness sheets): updated in place, not appended twice
apply_block() { # apply_block <rel> <block name>
  local f="$SW_ROOM/$1"
  [ -f "$f" ] || { warning "$1 not found; no pointer written"; return 0; }
  python3 "$STAGER" block "$f" "$STAGE/$2.block" "$STAGE/block.out" || die "cannot patch $1"
  if cmp -s "$STAGE/block.out" "$f"; then good "$1 already carries the current block"
  else journal_before "$f"; cp "$STAGE/block.out" "$f"; good "$1 patched (backup kept)"; fi
}
for t in $BLOCK_TARGETS; do apply_block "${t%=*}" "${t#*=}"; done
# dsh sheet: exists after the dsh patch (or from an earlier --dsh-room run)
[ ! -f "$SW_ROOM/room/harness/dsh-harness.md" ] || apply_block "room/harness/dsh-harness.md" pointer

journal_before "$MANIFEST"; cp "$NEW_MANIFEST" "$MANIFEST"
ARMED=0   # everything below touches Paseo or runs seatwork's own installer: not ours to roll back

# ================================================================ D. side effects
if [ "$DSH_PERSONAL" = 1 ] && [ "$SKIP_CHECKS" = 0 ]; then
  section "dsh (tier 1): the personal provider in Paseo"
  if [ "$DSH" = 0 ]; then
    warning "dsh not on PATH — skipping the deepseek-harness provider (install + configure dsh first)"
  elif paseo plugin ls --json 2>/dev/null | jq -e '.[]? | select(.id == "deepseek-harness")' >/dev/null 2>&1; then
    good "deepseek-harness provider already installed (paseo plugin ls)"
  elif paseo plugin add geoqiao/deepseek-harness >/dev/null 2>&1; then
    good "deepseek-harness provider added — dsh is now a Paseo provider (personal)"
  else warning "could not add deepseek-harness (registry/network?); add by hand: paseo plugin add geoqiao/deepseek-harness"
  fi
fi

if [ "$RUN_SEATWORK" = 1 ]; then
  section "Running seatwork install.sh (providers, profiles, plugin, daemon reload)"
  SW_FLAGS=()
  # seatwork remembers HQ/watcher in setup.json: the kit sets them on a first install, or when you pass a flag, never on a re-run
  if [ -n "$WATCHER" ]; then SW_FLAGS+=(--watcher "$WATCHER")
  elif [ ! -f "$ROOM_HOME/setup.json" ]; then SW_FLAGS+=(--watcher shadow); fi
  [ -f "$ROOM_HOME/setup.json" ] || SW_FLAGS+=(--hq default)
  if [ "$KEEP_FEATURES" = 1 ]; then SW_FLAGS+=(--no-daemon-policy); good "daemon features kept: only the room-required switches (mcp enabled + injectIntoAgents, pluginsEnabled) are set"; fi
  (cd "$SW_ROOM" && ./install.sh ${SW_FLAGS[@]+"${SW_FLAGS[@]}"}) || die "seatwork installer failed — the kit's files are in place; fix what it names, then re-run godkit install.sh"
fi

# ================================================================ E. verify
section "Verifying"
lens_line="$(sed -n 's/^  lens:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SW_ROOM/paseo/seats.yml" | head -1)"
case "$lens_line" in
  *dsh*) good "seats.yml: lens carries dsh (a DeepSeek lens against the Claude lens)" ;;
  *pi*)  good "seats.yml: lens carries pi (pair is possible if pi's model is not Anthropic)" ;;
  *) warning "seats.yml lens is '$lens_line' — two-axis review needs two families" ;;
esac
[ -f "$SW_ROOM/room/rules/godkit-engineering-standards.md" ] \
  && good "standards bar in place" || warning "standards bar missing"
for t in $BLOCK_TARGETS; do
  f="$SW_ROOM/${t%=*}"
  if grep -qF "GODKIT:begin" "$f" && ! grep -qF "<ROOM_DIR>" "$f"; then good "${t%=*}: godkit block present, path rendered"
  else warning "${t%=*}: godkit block missing or still holds <ROOM_DIR>"; fi
done
if grep -qE "_CLAUDE_MODEL_|_PI_MODEL_|_DSH_MODEL_" "$SW_ROOM/room/models.json"; then
  warning "room/models.json still carries placeholders — the room will refuse every seat"
elif ! jq -e . "$SW_ROOM/room/models.json" >/dev/null 2>&1; then
  warning "room/models.json is not valid JSON — the room will refuse seats"
elif cmp -s "$SW_ROOM/room/models.json" "$RENDERED_MODELS"; then
  good "room/models.json: valid, equals this run's render (claude=$CLAUDE_MODEL pi=$PI_MODEL)"
else
  warning "room/models.json is valid but is not this run's render (it is yours, or from other model ids); the room uses it as it is"
fi
if [ "$(jq -r --arg c "$CLAUDE_MODEL" '[.[] | select((.provider|startswith("claude-")) and .model != $c)] | length' "$SW_ROOM/paseo/profiles.json" 2>/dev/null)" = 0 ]; then
  good "paseo/profiles.json: claude profiles use $CLAUDE_MODEL"
else
  warning "paseo/profiles.json names a claude model other than $CLAUDE_MODEL (yours, or not rendered): the app's agent profiles may point at a model your claude lacks"
fi
if [ "$DSH_ROOM" = 1 ]; then
  [ "$(patch_state)" = applied ] && good "dsh patch: fully applied (checked in reverse against the patch file)" \
    || warning "dsh patch is not fully applied — dsh seats will not work"
  grep -q '"dsh"' "$SW_ROOM/paseo/policy.json" \
    && good "policy.json carries the dsh runtime block" || warning "policy.json lost the dsh block"
fi

section "Done"
printf '  %d ok, %d warning(s), %d file(s) left alone\n' "$ok" "$warn" "$left_alone"
[ -d "$BK_DIR" ] && printf '  backups of replaced files: %s\n' "$BK_DIR"
printf '\n'
if [ "$DSH_ROOM" = 1 ]; then
cat <<'NEXT'
  Next:
    1.  paseo reload  (if seatwork's installer did not already)
    2.  in an agent on the HQ Supervisor profile (hq-seatwork project):
          "set up project <X>"          — once per project
          (the law this writes carries the godkit lines; a project whose law was written
           before this install needs those lines added by hand — see delta/law/)
    3.  in YOUR OWN session (personal, with mp-skills installed):
          /setup-matt-pocock-skills     — once per repo
          /grill-with-docs → /to-spec → /to-tickets
    4.  hand the room the artifacts, in the project's Supervisor profile:
          "Spec and tickets are at .scratch/<feature>/issues/ — run the pipeline.
           Integration branch: integration/<feature> from <base>; the Lead may merge to it
           locally (no push, no deploy); the base branch never moves."
    5.  dsh seats: first turn on a fresh seat bootstraps its acp profile (slow once);
        if a dsh seat starts with no room tools, dsh's ACP refused mcpServers — set
        policy.json dsh.runtime.mcpServers = false, re-run this installer, and use
        dsh seats for reading/review only (they keep NO room tools).
    6.  watch: paseo app · seat stats via HQ ("watcher stats")
    7.  after the first real feature: retro in your own session (mp-skills /retro),
        then decide whether to flip the watcher from shadow to on.
NEXT
else
cat <<'NEXT'
  Next:
    1.  paseo reload  (if seatwork's installer did not already)
    2.  in an agent on the HQ Supervisor profile (hq-seatwork project):
          "set up project <X>"          — once per project
          (the law this writes carries the godkit lines; a project whose law was written
           before this install needs those lines added by hand — see delta/law/)
    3.  in YOUR OWN Claude session (personal, with mp-skills installed):
          /setup-matt-pocock-skills     — once per repo
          /grill-with-docs → /to-spec → /to-tickets
    4.  hand the room the artifacts, in the project's Supervisor profile:
          "Spec and tickets are at .scratch/<feature>/issues/ — run the pipeline.
           Integration branch: integration/<feature> from <base>; the Lead may merge to it
           locally (no push, no deploy); the base branch never moves."
    5.  dsh in Paseo (personal, tier 1): open any agent with the DeepSeek Harness provider;
        dsh room seats (tier 2) come with: bash install.sh --dsh-room --dsh-model <id>
    6.  watch: paseo app · seat stats via HQ ("watcher stats")
    7.  after the first real feature: retro in your own session (mp-skills /retro),
        then decide whether to flip the watcher from shadow to on.
NEXT
fi
