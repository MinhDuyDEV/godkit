#!/usr/bin/env bash
# GODKIT installer: turns a seatwork clone into the godkit pipeline room.
#
#   claude + pi + dsh · spec → tickets → build → two-axis review → ship → retro
#
# What it does (idempotent, backs everything up, never leaves a broken copy):
#   1. checks: paseo, claude, pi, dsh, jq, git, python3+PyYAML, a seatwork clone
#   2. dsh (tier 1, default on): adds the personal provider `geoqiao/deepseek-harness`
#      to Paseo — dsh sessions in the app, no room changes. Skip with --no-dsh-personal.
#   3. dsh (tier 2, opt-in, experimental): --dsh-room applies dsh/seatwork-dsh.patch so
#      `dsh-peer` / `dsh-lens` become room seats (isolated DSH_HOME, no user cordis patch,
#      room tools through injected MCP). Verified: typecheck + seatwork's 90 tests.
#   4. writes delta/seats.yml → slp-room/paseo/seats.yml, renders delta/models.json
#      (places _CLAUDE_MODEL_ / _PI_MODEL_ / — with --dsh-room — _DSH_MODEL_ from flags
#      or env, or asks once)
#   5. copies the godkit skills (5) into slp-room/room/skills/{lead,peer}/, the standards
#      bar into room/rules/, and appends the marked law + harness-sheet patches
#   6. runs seatwork's own ./install.sh (--hq default, --watcher as chosen)
#   7. verifies and prints the next steps
#
# Flags:
#   --seatwork-dir PATH      (default: ../seatwork next to this script, or $SEATWORK_DIR)
#   --claude-model ID        (default: $GODKIT_CLAUDE_MODEL, else asks once)
#   --pi-model ID            (default: $GODKIT_PI_MODEL, else asks once)
#   --dsh-model ID           (default: $GODKIT_DSH_MODEL, else asks once; --dsh-room only)
#   --dsh-room               patch seatwork so dsh holds room seats (tier 2, experimental)
#   --no-dsh-personal        skip tier 1 (do not add the deepseek-harness Paseo plugin)
#   --watcher shadow|on|off  (default: shadow — it logs, it mails nobody)
#   --force                  replace files / re-apply the dsh patch over user edits
#   --skip-checks            advance use/CI: skip the paseo/claude/pi/dsh/jq checks
#   --skip-dsh-tests         with --dsh-room: do not typecheck+test the patched plugin
#   --keep-daemon-features   seatwork installs with --no-daemon-policy: the room's room-required
#                            switches (daemon.mcp.enabled + injectIntoAgents + pluginsEnabled) still
#                            apply, so your browser tools, terminal hooks, dictation/voice mode and
#                            Paseo's bundled-skills selection stay exactly as they are now
#   --skip-seatwork-install  advance use: only place files, don't run seatwork's installer
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHER="shadow"; SW_DIR=""; CLAUDE_MODEL=""; PI_MODEL=""; DSH_MODEL=""; FORCE=0; RUN_SEATWORK=1
DSH_PERSONAL=1; DSH_ROOM=0; DSH_TESTS=1; KEEP_FEATURES=0

ok=0; warn=0
say()     { printf '  %s\n' "$*"; }
good()    { ok=$((ok+1));  printf '  ok    %s\n' "$*"; }
warning() { warn=$((warn+1)); printf '  warn  %s\n' "$*"; }
die()     { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
section() { printf '\n%s\n' "$*"; }

SKIP_CHECKS=0
while [ $# -gt 0 ]; do case "$1" in
  --seatwork-dir) SW_DIR="$2"; shift 2 ;;
  --claude-model) CLAUDE_MODEL="$2"; shift 2 ;;
  --pi-model)     PI_MODEL="$2"; shift 2 ;;
  --dsh-model)    DSH_MODEL="$2"; shift 2 ;;
  --dsh-room)     DSH_ROOM=1; shift ;;
  --dsh-personal) DSH_PERSONAL=1; shift ;;
  --no-dsh-personal) DSH_PERSONAL=0; shift ;;
  --skip-dsh-tests) DSH_TESTS=0; shift ;;
  --keep-daemon-features) KEEP_FEATURES=1; shift ;;
  --watcher)      WATCHER="$2"; shift 2 ;;
  --force)        FORCE=1; shift ;;
  --skip-checks)  SKIP_CHECKS=1; shift ;;
  --skip-seatwork-install) RUN_SEATWORK=0; shift ;;
  *) die "unknown flag: $1" ;;
esac; done

backup() { [ -e "$1" ] && cp "$1" "$1.godkit.bak.$(date +%s)"; }

# ---------------------------------------------------------------- 1. checks
section "Checking what is installed"

[ "$WATCHER" = off ] || [ "$WATCHER" = shadow ] || [ "$WATCHER" = on ] \
  || die "--watcher must be off, shadow or on"


if [ "$SKIP_CHECKS" = 1 ]; then
  warning "checks skipped (--skip-checks): placing files only"
  command -v jq >/dev/null 2>&1 || die "jq is still required to render models.json"
  [ "$DSH_ROOM" = 0 ] || [ "$SKIP_CHECKS" = 1 ] || true
else
  command -v paseo >/dev/null 2>&1 || die "paseo is not on PATH. Install it: https://paseo.sh"
  good "paseo: $(paseo --version 2>/dev/null || echo 'version unknown') — the room needs >= 0.10.3"
  CLAUDE=0; PI=0; DSH=0
  command -v claude >/dev/null 2>&1 && CLAUDE=1 || warning "claude not on PATH (HQ/Supervisor/Lead run on claude seats)"
  command -v pi     >/dev/null 2>&1 && PI=1     || warning "pi not on PATH (the lens pool loses one family)"
  command -v dsh    >/dev/null 2>&1 && DSH=1    || warning "dsh not on PATH (no DeepSeek tier; --dsh-room needs it)"
  [ "$CLAUDE" = 1 ] || die "claude is required (claude auth login once)"
  command -v jq >/dev/null 2>&1 || die "jq missing"
  command -v git >/dev/null 2>&1 || die "git missing (the dsh room patch applies through it)"
  python3 -c "import yaml" >/dev/null 2>&1 || die "python3 with PyYAML missing"
  if [ "${DSH:-0}" = 1 ] && [ "$DSH_ROOM" = 1 ]; then
    dshv="$(dsh --version 2>/dev/null | head -1 | tr -dc '0-9.rc-')"
    major="$(echo "$dshv" | cut -d. -f1)"; minor="$(echo "$dshv" | cut -d. -f2 | cut -d- -f1)"
    if [ "${major:-0}" -lt 2 ]; then
      warning "dsh $dshv is below what the room's ACP contracts were verified on; prefer dsh >= 0.2.0-rc.1 (piggery's floor) before real work"
    else good "dsh: $dshv"; fi
  fi
fi

[ -n "$SW_DIR" ] || SW_DIR="${SEATWORK_DIR:-$SRC/../seatwork}"
SW_DIR="$(cd "$SW_DIR" && pwd)"
[ -f "$SW_DIR/slp-room/install.sh" ] || die "no seatwork clone at $SW_DIR (git clone https://github.com/sting9k/seatwork.git)"
good "seatwork clone: $SW_DIR"

# ---------------------------------------------------------------- 2. dsh tier 1 — personal provider
if [ "$DSH_PERSONAL" = 1 ] && [ "$SKIP_CHECKS" = 0 ]; then
  section "dsh (tier 1): the personal provider in Paseo"
  if [ "${DSH:-0}" = 0 ]; then
    warning "dsh not on PATH — skipping the deepseek-harness provider (install + configure dsh first)"
  elif paseo plugin ls --json 2>/dev/null | jq -e '.[]? | select(.id == "deepseek-harness")' >/dev/null 2>&1; then
    good "deepseek-harness provider already installed (paseo plugin ls)"
  else
    if paseo plugin add geoqiao/deepseek-harness >/dev/null 2>&1; then
      good "deepseek-harness provider added — dsh is now a Paseo provider (personal)"
    else warning "could not add deepseek-harness (registry/network?); add by hand: paseo plugin add geoqiao/deepseek-harness"
    fi
  fi
fi

# ---------------------------------------------------------------- 3. model ids
if [ -z "$CLAUDE_MODEL" ]; then CLAUDE_MODEL="${GODKIT_CLAUDE_MODEL:-}"; fi
if [ -z "$PI_MODEL" ];     then PI_MODEL="${GODKIT_PI_MODEL:-}"; fi
if [ -z "$DSH_MODEL" ];    then DSH_MODEL="${GODKIT_DSH_MODEL:-}"; fi
if [ -z "$CLAUDE_MODEL" ] || [ -z "$PI_MODEL" ] || { [ "$DSH_ROOM" = 1 ] && [ -z "$DSH_MODEL" ]; }; then
  printf '\n  Model ids the room will pin (they must exist in each harness catalog).\n'
  printf '  The lens pair is meant to be TWO families, and dsh-peer carries the cross-family tier.\n'
fi
while [ -z "$CLAUDE_MODEL" ]; do printf '  claude model id (e.g. claude-opus-4-6): ' ; read -r CLAUDE_MODEL; done
while [ -z "$PI_MODEL" ];     do printf '  pi model id (lens pool, optional): '       ; read -r PI_MODEL; done
if [ "$DSH_ROOM" = 1 ]; then
  while [ -z "$DSH_MODEL" ]; do printf '  dsh model id (cross-family tier + lens pair; as dsh reports it): ' ; read -r DSH_MODEL; done
  good "models: claude=$CLAUDE_MODEL  pi=$PI_MODEL  dsh=$DSH_MODEL"
else
  good "models: claude=$CLAUDE_MODEL  pi=$PI_MODEL"
fi

# ---------------------------------------------------------------- 4. place files
section "Placing godkit files"
# A target that differs from the kit's copy is replaced when it is still
# seatwork's original (unmodified in git), or with --force. A file the user
# edited by hand is never silently rewritten.
user_modified() { # user_modified <relpath> -> 0 when the file has uncommitted changes
  [ -d "$SW_DIR/.git" ] && ! [ -z "$(git -C "$SW_DIR" status --porcelain -- "$1" 2>/dev/null)" ]
}
place() { # place <src-rel> <dst-rel>
  local s="$SRC/delta/$1" d="$SW_DIR/slp-room/$2"
  mkdir -p "$(dirname "$d")"
  if [ -e "$d" ] && ! cmp -s "$s" "$d"; then
    if [ "$FORCE" = 1 ]; then backup "$d"; cp "$s" "$d"; good "$2 replaced (--force)"
    elif user_modified "slp-room/$2"; then warning "$2 exists, was edited by hand, and differs; left alone (re-run with --force)"
    else good "$2 is seatwork's original and differs from the kit's; kit copy replaces it"; backup "$d"; cp "$s" "$d"; fi
    return 0
  fi
  if [ -e "$d" ]; then good "$2 already current"; else cp "$s" "$d"; good "$2"; fi
}

SEATS_SRC="seats.yml"; MODELS_SRC="models.json"
if [ "$DSH_ROOM" = 1 ]; then SEATS_SRC="seats.dsh.yml"; MODELS_SRC="models.dsh.json"; fi
SEATS_YML_SRC="$SRC/delta/$SEATS_SRC"
[ -f "$SEATS_YML_SRC" ] || die "missing kit file: $SEATS_YML_SRC"
[ -f "$SRC/delta/$MODELS_SRC" ] || die "missing kit file: $MODELS_SRC"

place "$SEATS_SRC" "paseo/seats.yml"
if [ -f "$SEATS_YML_SRC" ]; then
  rendered="$(mktemp)"
  sed_arg=(-e "s|_CLAUDE_MODEL_|$CLAUDE_MODEL|g" -e "s|_PI_MODEL_|$PI_MODEL|g")
  if [ "$DSH_ROOM" = 1 ]; then sed_arg+=(-e "s|_DSH_MODEL_|$DSH_MODEL|g"); fi
  sed "${sed_arg[@]}" "$SRC/delta/$MODELS_SRC" > "$rendered"
  jq -e . "$rendered" >/dev/null 2>&1 || die "rendered models.json is not valid JSON — this is a kit bug"
  if [ "$(grep -c "_CLAUDE_MODEL_\|_PI_MODEL_\|_DSH_MODEL_" "$rendered")" -gt 0 ]; then
    die "a placeholder survived rendering — malformed model id with a slash or quotes?"
  fi
  d="$SW_DIR/slp-room/room/models.json"
  if [ -e "$d" ] && ! cmp -s "$rendered" "$d"; then
    if [ "$FORCE" = 1 ]; then backup "$d"; mv "$rendered" "$d"; good "room/models.json rendered+replaced (--force)"
    elif user_modified "slp-room/room/models.json"; then warning "room/models.json was edited by hand and differs; left alone (re-run with --force)"; rm -f "$rendered"
    else backup "$d"; mv "$rendered" "$d"; good "room/models.json rendered (was seatwork's original; backup kept)"
    fi
  else
    if [ -e "$d" ]; then rm -f "$rendered"; good "room/models.json already current"
    else mv "$rendered" "$d"; good "room/models.json rendered"; fi
  fi
fi

for s in "skills/lead/slp-ticket-frontier/SKILL.md" \
         "skills/lead/slp-refinery/SKILL.md" \
         "skills/lead/slp-two-axis-review/SKILL.md" \
         "skills/lead/slp-two-axis-review/references/two-axis-formats.md" \
         "skills/peer/slp-tdd/SKILL.md" \
         "skills/peer/slp-diagnose/SKILL.md"; do place "$s" "room/$s"; done
place "rules/godkit-engineering-standards.md" "room/rules/godkit-engineering-standards.md"

# ---------------------------------------------------------------- 4b. dsh tier 2 — the room patch
if [ "$DSH_ROOM" = 1 ]; then
  section "dsh (tier 2): patching seatwork so dsh holds room seats (experimental)"
  patch="$SRC/dsh/seatwork-dsh.patch"
  [ -f "$patch" ] || die "dsh patch missing: $patch — this is a kit bug"
  ( cd "$SW_DIR" && git apply --check "$patch" >/dev/null 2>&1 ) \
    && APPLIES=1 || APPLIES=0
  if grep -q '"dsh"' "$SW_DIR/slp-room/plugin/server/seats.ts"; then
    good "seatwork dsh patch: already applied"
  elif [ "$APPLIES" = 0 ]; then
    if [ "$FORCE" = 1 ]; then
      ( cd "$SW_DIR" && git apply "$patch" ) || die "the dsh patch does not apply even with --force — the seatwork clone has drifted; regenerate dsh/seatwork-dsh.patch"
      good "seatwork dsh patch applied (--force)"
    else
      die "the dsh patch no longer applies (the seatwork clone has drifted). Re-clone seatwork, or regenerate the patch (see godkit/docs/DSH-PASEO.md §regenerating)."
    fi
  else
    ( cd "$SW_DIR" && git apply "$patch" ) || die "git apply failed unexpectedly"
    good "seatwork dsh patch applied (uncommitted in the clone; 'git -C $SW_DIR diff' reviews it, 'git checkout -- . +' reverts all of it)"
  fi
  if [ "$DSH_TESTS" = 1 ] && [ "$SKIP_CHECKS" = 0 ]; then
    if ( cd "$SW_DIR/slp-room/plugin" && npm install --no-audit --no-fund >/dev/null 2>&1 && npm run typecheck >/dev/null 2>&1 && npm test >/dev/null 2>&1 ); then
      good "patched plugin: npm install + typecheck + tests pass (90/90)"
    else
      warning "the patched plugin did not verify locally (npm/typecheck/tests) — see $SW_DIR/slp-room/plugin; the room keeps working, dsh seats may not"
    fi
  fi
fi

# ---------------------------------------------------------------- 5. marked patches
section "Patching the law template and the harness sheets"
patch_after_marker() { # patch_after_marker <file> <marker-substring> <patch-file>
  local f="$SW_DIR/slp-room/$1" m="$2" p="$SRC/delta/$3"
  if [ ! -f "$f" ]; then
    if [ "$1" = "room/harness/dsh-harness.md" ] && [ "$DSH_ROOM" = 1 ]; then die "dsh-harness.md missing — the dsh patch did not apply?"; fi
    die "expected file missing: $f (is this a seatwork clone?)"
  fi
  if grep -qF "$m" "$f"; then good "$1 already patched"
  else backup "$f"; cat "$p" >> "$f"; good "$1 patched (backup kept)"; fi
}
patch_after_marker "room/skills/supervisor/slp-project-law/references/project-law.md" \
  "GODKIT additions" "law/godkit-law-additions.md"
patch_after_marker "room/harness/claude-harness.md" "GODKIT pointer" "law/godkit-harness-pointer.md"
patch_after_marker "room/harness/pi-harness.md" "GODKIT pointer" "law/godkit-harness-pointer.md"
if sed -n '/^seats:/,/^restrict/p' "$SW_DIR/slp-room/paseo/seats.yml" | grep -Eq "dsh"; then
  patch_after_marker "room/harness/dsh-harness.md" "GODKIT pointer" "law/godkit-harness-pointer.md"
fi

# ---------------------------------------------------------------- 6. seatwork's own installer
if [ "$RUN_SEATWORK" = 1 ]; then
  section "Running seatwork install.sh (providers, profiles, plugin, daemon reload)"
  SW_FLAGS=(--hq default --watcher "$WATCHER")
  if [ "$KEEP_FEATURES" = 1 ]; then SW_FLAGS+=(--no-daemon-policy); good "daemon features kept: only the room-required switches (mcp enabled + injectIntoAgents, pluginsEnabled) are set"; fi
  (cd "$SW_DIR/slp-room" && ./install.sh "${SW_FLAGS[@]}") || die "seatwork installer failed — fix what it names, then re-run godkit install.sh"
fi

# ---------------------------------------------------------------- 7. verify
section "Verifying"
lens_line="$(sed -n 's/^  lens:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SW_DIR/slp-room/paseo/seats.yml" | head -1)"
case "$lens_line" in
  *dsh*) good "seats.yml: lens carries dsh (a DeepSeek lens against the Claude lens)" ;;
  *pi*)  good "seats.yml: lens carries pi (pair is possible if pi's model is not Anthropic)" ;;
  *) warning "seats.yml lens is '$lens_line' — two-axis review needs two families" ;;
esac
[ -f "$SW_DIR/slp-room/room/rules/godkit-engineering-standards.md" ] \
  && good "standards bar in place" || warning "standards bar missing"
grep -q "GODKIT additions" "$SW_DIR/slp-room/room/skills/supervisor/slp-project-law/references/project-law.md" \
  && good "law template carries the godkit lines" || warning "law template not patched"
PLACEHOLDER_LEFT=0
{ grep -q "_CLAUDE_MODEL_\|_PI_MODEL_" "$SW_DIR/slp-room/room/models.json" \
  || { [ "$DSH_ROOM" = 1 ] && grep -q "_DSH_MODEL_" "$SW_DIR/slp-room/room/models.json"; }; } && PLACEHOLDER_LEFT=1
if [ "$PLACEHOLDER_LEFT" = 1 ]; then
  warning "room/models.json still carries placeholders — the room will refuse every seat"
elif jq -e . "$SW_DIR/slp-room/room/models.json" >/dev/null 2>&1; then
  good "room/models.json: rendered, valid"
else
  warning "room/models.json is not valid JSON — the room will refuse seats"
fi
if [ "$DSH_ROOM" = 1 ]; then
  grep -q '"dsh"' "$SW_DIR/slp-room/plugin/server/seats.ts" \
    && good "seatwork plugin carries the dsh harness" || warning "seatwork plugin lost the dsh harness"
  grep -q '"dsh"' "$SW_DIR/slp-room/paseo/policy.json" \
    && good "policy.json carries the dsh runtime block" || warning "policy.json lost the dsh block"
fi

section "Done"
printf '  %d ok, %d warning(s)\n\n' "$ok" "$warn"
if [ "$DSH_ROOM" = 1 ]; then
cat <<'NEXT'
  Next:
    1.  paseo reload  (if seatwork's installer did not already)
    2.  in an agent on the HQ Supervisor profile (hq-seatwork project):
          "set up project <X>"          — once per project
    3.  in YOUR OWN session (personal, with mp-skills installed):
          /setup-matt-pocock-skills     — once per repo
          /grill-with-docs → /to-spec → /to-tickets
    4.  hand the room the artifacts, in the project's Supervisor profile:
          "Spec and tickets from the godkit intake are at .scratch/<feature>/issues/ —
           run the pipeline. Check the law's integration branch first."
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
    3.  in YOUR OWN Claude session (personal, with mp-skills installed):
          /setup-matt-pocock-skills     — once per repo
          /grill-with-docs → /to-spec → /to-tickets
    4.  hand the room the artifacts, in the project's Supervisor profile:
          "Spec and tickets from the godkit intake are at .scratch/<feature>/issues/ —
           run the pipeline. Check the law's integration branch first."
    5.  dsh in Paseo (personal, tier 1): open any agent with the DeepSeek Harness provider;
        dsh room seats (tier 2) come with: bash install.sh --dsh-room --dsh-model <id>
    6.  watch: paseo app · seat stats via HQ ("watcher stats")
    7.  after the first real feature: retro in your own session (mp-skills /retro),
        then decide whether to flip the watcher from shadow to on.
NEXT
fi