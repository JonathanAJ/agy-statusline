#!/usr/bin/env bash
# Antigravity CLI status line
# Reads the state JSON on stdin, renders an adaptive one/two-line status bar.
# https://antigravity.google/docs/cli/statusline/

set -u
input=$(cat)
if [[ -n "${AGY_DEBUG:-}" || -f /tmp/agy_statusline_debug ]]; then
  printf '%s\n' "$input" > /tmp/agy_statusline_last.json 2>/dev/null || true
fi

# ---- parse everything in one jq pass -----------------------------------------
# \x1f (unit separator) keeps empty fields aligned — tab-IFS would collapse them
IFS=$'\x1f' read -r STATE MODEL DIR WIDTH CTX_PCT CTX_SIZE IN_TOK OUT_TOK \
  VCS_TYPE BRANCH DIRTY SANDBOX ARTIFACTS TASKS SUBAGENTS CYCLE_MODE TIER \
  QUOTA_FRAC QUOTA_RESET EXCEEDS VIM_MODE <<EOF || true
$(jq -r '
  def n0: . // 0;
  # all fields defaulted so the join never emits fewer than 21 values
  [ (.agent_state // "idle"),
    (.model.display_name // .model.id // "?"),
    (.workspace.current_dir // .cwd // ""),
    (.terminal_width // 80),
    (.context_window.used_percentage // 0),
    (.context_window.context_window_size // 0),
    (.context_window.total_input_tokens | n0),
    (.context_window.total_output_tokens | n0),
    (.vcs.type // ""),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.sandbox.enabled // false),
    (.artifact_count | n0),
    (.task_count | n0),
    ((.subagents // []) | length),
    (.cycle_mode // ""),
    (.plan_tier // ""),
    (([.quota // {} | to_entries[].value] | min_by(.remaining_fraction) | .remaining_fraction) // ""),
    (([.quota // {} | to_entries[].value] | min_by(.remaining_fraction) | .reset_in_seconds) // ""),
    (.exceeds_200k_tokens // false),
    (.vim_mode // .vim.mode // "")
  ] | map(tostring) | join("\u001f")' <<<"$input" 2>/dev/null)
EOF

# fallbacks in case jq failed on malformed input
STATE=${STATE:-idle}; MODEL=${MODEL:-?}; DIR=${DIR:-}; WIDTH=${WIDTH:-80}
CTX_PCT=${CTX_PCT:-0}; IN_TOK=${IN_TOK:-0}; OUT_TOK=${OUT_TOK:-0}
VCS_TYPE=${VCS_TYPE:-}; BRANCH=${BRANCH:-}; DIRTY=${DIRTY:-false}
SANDBOX=${SANDBOX:-false}; ARTIFACTS=${ARTIFACTS:-0}; TASKS=${TASKS:-0}
SUBAGENTS=${SUBAGENTS:-0}; CYCLE_MODE=${CYCLE_MODE:-}; TIER=${TIER:-}
QUOTA_FRAC=${QUOTA_FRAC:-}; QUOTA_RESET=${QUOTA_RESET:-}
EXCEEDS=${EXCEEDS:-false}; VIM_MODE=${VIM_MODE:-}

# ---- palette (256-color, tuned for a dark scheme) ----------------------------
R=$'\e[0m'; B=$'\e[1m'; DIM=$'\e[2m'
FG=$'\e[38;5;252m'      # main text
MUT=$'\e[38;5;244m'     # muted
SEP=$'\e[38;5;238m'     # separators
GRN=$'\e[38;5;114m'; YLW=$'\e[38;5;179m'; ORG=$'\e[38;5;209m'
RED=$'\e[38;5;203m'; CYN=$'\e[38;5;80m';  BLU=$'\e[38;5;111m'
MAG=$'\e[38;5;176m'; PNK=$'\e[38;5;218m'
sep="${SEP} │ ${R}"

# ---- agent state -------------------------------------------------------------
case "$STATE" in
  idle)         state_str="${GRN}${B}●${R} ${GRN}ready${R}" ;;
  thinking)     state_str="${MAG}${B}✳${R} ${MAG}thinking${R}" ;;
  working)      state_str="${CYN}${B}⚙${R} ${CYN}working${R}" ;;
  tool_use)     state_str="${BLU}${B}⚒${R} ${BLU}tool${R}" ;;
  initializing) state_str="${MUT}◌ init${R}" ;;
  *)            state_str="${MUT}● ${STATE}${R}" ;;
esac

# ---- model (compact: strip "Gemini ", turn "(High)" into ·High) --------------
model=${MODEL#Gemini }
model=$(sed -E 's/ *\((.*)\)/·\1/' <<<"$model")
model_str="${PNK}${model}${R}"

# ---- directory (~-shortened, last 2 components) ------------------------------
dir=${DIR/#$HOME/\~}
IFS='/' read -ra parts <<<"$dir"
np=${#parts[@]}
if (( np > 2 )); then dir="${parts[np-2]}/${parts[np-1]}"; fi
dir_str=""
[[ -n $dir ]] && dir_str="${FG}${dir}${R}"

# ---- git: branch, dirty, ahead/behind ----------------------------------------
git_str=""
if [[ -n $BRANCH ]]; then
  flags=""
  [[ $DIRTY == "true" ]] && flags="${YLW}✚${R}"
  if [[ $VCS_TYPE == "git" && -n $DIR ]]; then
    ab=$(cd "$DIR" 2>/dev/null && git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
    if [[ ${ab:-} =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
      behind=${ab%%$'\t'*}; ahead=${ab##*$'\t'}
      (( ahead  > 0 )) && flags+="${CYN}⇡${ahead}${R}"
      (( behind > 0 )) && flags+="${ORG}⇣${behind}${R}"
    fi
  fi
  git_str="${BLU} ${BRANCH}${R}${flags}"
fi

# ---- context bar -------------------------------------------------------------
pct=${CTX_PCT%.*}; pct=${pct:-0}
if   (( pct < 50 )); then cx=$GRN
elif (( pct < 75 )); then cx=$YLW
elif (( pct < 90 )); then cx=$ORG
else                      cx=$RED; fi
barw=10
fill=$(( pct * barw / 100 )); (( fill > barw )) && fill=$barw
rem=$(( (pct * barw) % 100 ))   # fractional last block: ▓ ≥75, ▒ ≥50, ░ ≥25
bar=""
for ((i=0;i<barw;i++)); do
  if   (( i < fill ));  then bar+="█"
  elif (( i == fill )); then
    if   (( rem >= 75 )); then bar+="▓"
    elif (( rem >= 50 )); then bar+="▒"
    elif (( rem >= 25 )); then bar+="░"
    else                       bar+="·"
    fi
  else bar+="·"
  fi
done
ctx_str="${cx}${bar} ${pct}%${R}"
[[ $EXCEEDS == "true" ]] && ctx_str+=" ${RED}${B}⚠200k${R}"

# tokens, humanized (wide layouts only)
hum() { local t=$1
  if   (( t >= 1000000 )); then printf '%d.%dM' $((t/1000000)) $((t%1000000/100000))
  elif (( t >= 1000 ));    then printf '%dk' $((t/1000))
  else                          printf '%d' "$t"; fi
}
tok_str="${MUT}$(hum "$IN_TOK")↑ $(hum "$OUT_TOK")↓${R}"

# ---- quota + reset countdown -------------------------------------------------
quota_str=""
if [[ -n $QUOTA_FRAC ]]; then
  qpct=$(awk -v f="$QUOTA_FRAC" 'BEGIN{printf "%d", f*100}')
  if   (( qpct > 50 )); then qc=$GRN
  elif (( qpct > 20 )); then qc=$YLW
  else                       qc=$RED; fi
  quota_str="${qc}◔ ${qpct}%${R}"
  if [[ -n $QUOTA_RESET ]]; then
    s=${QUOTA_RESET%.*}
    if   (( s >= 86400 )); then rst="$((s/86400))d$((s%86400/3600))h"
    elif (( s >= 3600 ));  then rst="$((s/3600))h$((s%3600/60))m"
    else                        rst="$((s/60))m"; fi
    quota_str+="${MUT}·${rst}${R}"
  fi
  [[ -n $TIER ]] && quota_str+=" ${DIM}${TIER}${R}"
fi

# ---- counters / badges -------------------------------------------------------
extras=""
(( TASKS     > 0 )) && extras+="${CYN}▶${TASKS}${R} "
(( SUBAGENTS > 0 )) && extras+="${MAG}⛓${SUBAGENTS}${R} "
(( ARTIFACTS > 0 )) && extras+="${YLW}✦${ARTIFACTS}${R} "
[[ $SANDBOX == "true" ]] && extras+="${GRN}▣sbx${R} "
extras=${extras% }

mode_str=""
if [[ -n $CYCLE_MODE && $CYCLE_MODE != "null" && $CYCLE_MODE != "default" ]]; then
  case "$CYCLE_MODE" in
    plan)         mode_str="${MAG}${B}PLAN${R}" ;;
    accept-edits) mode_str="${YLW}${B}ACCEPT-EDITS${R}" ;;
    *)            mode_str="${DIM}$(tr '[:lower:]' '[:upper:]' <<<"$CYCLE_MODE")${R}" ;;
  esac
fi

vim_str=""
if [[ -n $VIM_MODE && $VIM_MODE != "null" ]]; then
  case "$VIM_MODE" in
    INSERT) vc=$GRN ;; NORMAL) vc=$BLU ;; *) vc=$MAG ;;
  esac
  vim_str="${vc}${B}[$VIM_MODE]${R}"
fi

# ---- assemble by terminal width ----------------------------------------------
join() { # join non-empty args with sep
  local out="" a
  for a in "$@"; do
    [[ -z $a ]] && continue
    [[ -n $out ]] && out+="$sep"
    out+="$a"
  done
  printf '%s' "$out"
}

if (( WIDTH >= 120 )); then
  join "$state_str" "$model_str" "$dir_str" "$git_str" \
       "$ctx_str $tok_str" "$quota_str" "$extras" "$mode_str" "$vim_str"
elif (( WIDTH >= 85 )); then
  join "$state_str" "$model_str" "$git_str" "$ctx_str" "$quota_str" "$mode_str" "$vim_str"
  printf '\n'
  join "$dir_str" "$tok_str" "$extras"
else
  join "$state_str" "$git_str" "${cx}${pct}%${R}" "$quota_str" "$vim_str"
fi
printf '\n'
