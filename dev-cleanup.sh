#!/usr/bin/env bash
set -euo pipefail

# dev-clean.sh
# Interactive macOS dev-machine cleanup script (React Native, Xcode, Docker, Node, caches).
#
# Features:
# - Interactive prompts per task (default)
# - Flags to run specific tasks: --only xcode-deriveddata,docker-prune,node-caches
# - Flags to skip tasks: --skip logs,spotlight
# - Non-interactive mode: --yes (run selected tasks without prompting)
# - List tasks: --list
# - Dry run: --dry-run (prints actions)
#
# Notes:
# - This script deletes regeneratable artifacts and caches. It does NOT touch your repos.
# - Some tasks require sudo.
# - Docker tasks require Docker CLI installed; some require Docker daemon running.

SCRIPT_NAME="$(basename "$0")"

# ---------- helpers ----------
color() {
  local code="$1"; shift
  if [ -t 1 ]; then
    printf "\033[%sm%s\033[0m" "$code" "$*"
  else
    printf "%s" "$*"
  fi
}
info() { echo "$(color 36 '[info]') $*"; }
warn() { echo "$(color 33 '[warn]') $*"; }
err()  { echo "$(color 31 '[err]')  $*" >&2; }
ok()   { echo "$(color 32 '[ok]')   $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="$1"
  local default="${2:-N}" # Y or N
  if [[ "${ASSUME_YES}" == "1" ]]; then
    info "$prompt -> auto-yes (--yes)"
    return 0
  fi
  local suffix="[y/N]"
  [[ "$default" == "Y" ]] && suffix="[Y/n]"
  while true; do
    read -r -p "$prompt $suffix " ans || true
    ans="${ans:-}"
    if [[ -z "$ans" ]]; then
      [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO)   return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

# runinfo: always executes even in dry-run (used for informational commands like du)
runinfo() {
  eval "$@"
}

bytes_free_human() {
  # df -h isn't consistent for scripting, but good enough for human display
  df -h / | awk 'NR==2 {print $4 " free (" $5 " used)"}'
}

section() {
  echo
  echo "$(color 35 '==>') $(color 1 "$1")"
  echo "$(color 90 "Disk: $(bytes_free_human)")"
}

# ---------- tasks ----------
task_desc() {
  case "$1" in
    xcode-deriveddata) echo "Delete Xcode DerivedData (safe, rebuilds later)" ;;
    ios-simulators)    echo "Delete iOS simulators (CoreSimulator) and unavailable devices" ;;
    cocoapods)         echo "Clear CocoaPods caches (~/Library/Caches/CocoaPods and ~/.cocoapods/repos)" ;;
    android)           echo "Clear Gradle caches (~/.gradle/caches) and Android AVDs" ;;
    node-caches)       echo "Clear Node/Expo/Metro/Yarn/pnpm caches" ;;
    tm-snapshots)      echo "Thin local Time Machine snapshots (may reclaim System Data)" ;;
    logs)              echo "Clear user and system logs (~/Library/Logs and /Library/Logs)" ;;
    homebrew)          echo "Homebrew cleanup (remove old formula versions and caches)" ;;
    docker-prune)      echo "Docker safe prune (docker system prune). Requires Docker daemon running" ;;
    spotlight)         echo "Spotlight reindex (overnight, high CPU). Rarely needed" ;;
    report)            echo "Report large dev directories (shows sizes, no deletion)" ;;
    *)                 echo "" ;;
  esac
}

task_fn() {
  # Convert task name to function name: hyphens -> underscores, prepend task_
  echo "task_${1//-/_}"
}

DEFAULT_ORDER=( \
  "report" \
  "xcode-deriveddata" \
  "ios-simulators" \
  "cocoapods" \
  "android" \
  "node-caches" \
  "tm-snapshots" \
  "logs" \
  "homebrew" \
  "docker-prune" \
  "spotlight" \
)

task_report() {
  section "Report"
  info "Showing sizes for common culprits."
  runinfo 'du -sh ~/Library/Developer 2>/dev/null || true'
  runinfo 'du -sh ~/Library/Developer/CoreSimulator 2>/dev/null || true'
  runinfo 'du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null || true'
  runinfo 'du -sh ~/.gradle/caches 2>/dev/null || true'
  runinfo 'du -sh ~/Library/Containers 2>/dev/null || true'
  if [[ -d ~/Library/Containers/com.docker.docker ]]; then
    runinfo 'du -sh ~/Library/Containers/com.docker.docker 2>/dev/null || true'
  fi
}

task_xcode_deriveddata() {
  section "Xcode DerivedData"
  local path="$HOME/Library/Developer/Xcode/DerivedData"
  if [[ ! -d "$path" ]]; then
    ok "No DerivedData directory found."
    return 0
  fi
  runinfo "du -sh \"$path\" 2>/dev/null || true"
  if confirm "Delete DerivedData at $path?"; then
    run "rm -rf \"$path\""
    ok "Deleted DerivedData."
  else
    info "Skipped DerivedData."
  fi
}

task_ios_simulators() {
  section "iOS Simulators"
  local path="$HOME/Library/Developer/CoreSimulator"
  if [[ ! -d "$path" ]]; then
    ok "No CoreSimulator directory found."
    return 0
  fi

  warn "Close Xcode and Simulator first to prevent immediate recreation."
  runinfo "du -sh \"$path\" 2>/dev/null || true"

  if need_cmd xcrun; then
    if confirm "Delete unavailable simulators/devices via 'xcrun simctl delete unavailable'?"; then
      run "xcrun simctl delete unavailable || true"
      ok "Deleted unavailable simulator devices."
    else
      info "Skipped simctl unavailable cleanup."
    fi
  else
    warn "xcrun not found, skipping simctl step."
  fi

  if confirm "Delete entire CoreSimulator directory (removes all simulators and data)?"; then
    if confirm "Are you sure? This will remove all simulator devices and app data." "N"; then
      run "rm -rf \"$path\""
      ok "Deleted CoreSimulator."
    else
      info "Skipped CoreSimulator deletion."
    fi
  else
    info "Skipped CoreSimulator deletion."
  fi
}

task_cocoapods() {
  section "CocoaPods"
  local cache="$HOME/Library/Caches/CocoaPods"
  local repos="$HOME/.cocoapods/repos"

  if [[ ! -d "$cache" ]] && [[ ! -d "$repos" ]]; then
    ok "No CocoaPods cache found."
    return 0
  fi

  [[ -d "$cache" ]] && runinfo "du -sh \"$cache\" 2>/dev/null || true"
  [[ -d "$repos" ]] && runinfo "du -sh \"$repos\" 2>/dev/null || true"

  if [[ -d "$cache" ]]; then
    if need_cmd pod; then
      if confirm "Clean CocoaPods cache via 'pod cache clean --all'?"; then
        run "pod cache clean --all"
        ok "Cleaned CocoaPods cache."
      else
        info "Skipped CocoaPods cache."
      fi
    else
      if confirm "Delete CocoaPods download cache ($cache)?"; then
        run "rm -rf \"$cache\""
        ok "Deleted CocoaPods cache."
      else
        info "Skipped CocoaPods cache."
      fi
    fi
  fi

  if [[ -d "$repos" ]]; then
    warn "Deleting spec repos means 'pod install' will re-clone them (slow first run)."
    if confirm "Delete CocoaPods spec repos ($repos)?"; then
      run "rm -rf \"$repos\""
      ok "Deleted CocoaPods spec repos."
    else
      info "Skipped CocoaPods spec repos."
    fi
  fi
}

task_android() {
  section "Android/Gradle caches"
  local gradle_cache="$HOME/.gradle/caches"
  local avd_dir="$HOME/.android/avd"

  if [[ ! -d "$gradle_cache" ]] && [[ ! -d "$avd_dir" ]]; then
    ok "No Android/Gradle cache found."
    return 0
  fi

  [[ -d "$gradle_cache" ]] && runinfo "du -sh \"$gradle_cache\" 2>/dev/null || true"
  [[ -d "$avd_dir" ]]      && runinfo "du -sh \"$avd_dir\" 2>/dev/null || true"

  if [[ -d "$gradle_cache" ]]; then
    warn "Deleting Gradle caches will slow the next Android build (re-downloads dependencies)."
    if confirm "Delete Gradle caches ($gradle_cache)?"; then
      run "rm -rf \"$gradle_cache\""
      ok "Deleted Gradle caches."
    else
      info "Skipped Gradle caches."
    fi
  fi

  if [[ -d "$avd_dir" ]]; then
    warn "Deleting AVDs removes all Android emulator devices and their data."
    if confirm "Delete Android Virtual Devices ($avd_dir)?"; then
      run "rm -rf \"$avd_dir\""
      ok "Deleted AVDs."
    else
      info "Skipped AVDs."
    fi
  fi
}

task_node_caches() {
  section "Node/Expo/Metro/Yarn/pnpm caches"
  local targets=(
    "$HOME/.npm"
    "$HOME/.cache/yarn" "$HOME/.cache/expo-cli" "$HOME/.cache/node"
    "$HOME/.yarn/cache"
    "$HOME/.pnpm-store"
    "$HOME/.expo" "$HOME/.metro"
    "/tmp/metro-*"
  )
  info "Targets:"
  for t in "${targets[@]}"; do echo "  - $t"; done
  warn "Downside: first install/build may be slower. Safe to regenerate."

  if confirm "Clear these caches?"; then
    run "rm -rf \"$HOME/.npm\" \"$HOME/.cache/yarn\" \"$HOME/.cache/expo-cli\" \"$HOME/.cache/node\" \"$HOME/.yarn/cache\" \"$HOME/.pnpm-store\" \"$HOME/.expo\" \"$HOME/.metro\""
    run "rm -rf /tmp/metro-* 2>/dev/null || true"
    ok "Cleared caches."
  else
    info "Skipped caches."
  fi
}

task_tm_snapshots() {
  section "Time Machine local snapshots"
  if ! need_cmd tmutil; then
    warn "tmutil not found. Skipping."
    return 0
  fi

  info "Listing local snapshots (if any):"
  runinfo "tmutil listlocalsnapshots / || true"

  warn "This affects only local snapshots, not external backups."
  if confirm "Thin local snapshots (may require sudo)?"; then
    run "sudo tmutil thinlocalsnapshots / 100000000000 4"
    ok "Thinned local snapshots (if any)."
  else
    info "Skipped Time Machine thinning."
  fi
}

task_logs() {
  section "Logs"
  warn "This deletes historical logs. It does not affect apps, but you lose old diagnostics."
  local user_logs="$HOME/Library/Logs"
  local system_logs="/Library/Logs"

  runinfo "du -sh \"$user_logs\" 2>/dev/null || true"
  runinfo "sudo du -sh \"$system_logs\" 2>/dev/null || true"

  if confirm "Clear user logs at $user_logs?"; then
    run "rm -rf \"$user_logs\"/*"
    ok "Cleared user logs."
  else
    info "Skipped user logs."
  fi

  if confirm "Clear system logs at $system_logs (requires sudo)?"; then
    run "sudo rm -rf \"$system_logs\"/*"
    ok "Cleared system logs."
  else
    info "Skipped system logs."
  fi
}

task_homebrew() {
  section "Homebrew"
  if ! need_cmd brew; then
    warn "brew not found. Skipping."
    return 0
  fi
  warn "Downside: removing cached bottles and old versions may reduce easy rollbacks."
  if confirm "Run 'brew cleanup -s'?"; then
    run "brew cleanup -s"
    ok "brew cleanup done."
  else
    info "Skipped brew cleanup."
  fi

  local cache
  cache="$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
  if [[ -d "$cache" ]]; then
    runinfo "du -sh \"$cache\" 2>/dev/null || true"
    if confirm "Delete Homebrew cache folder ($cache)?"; then
      run "rm -rf \"$cache\""
      ok "Deleted Homebrew cache."
    else
      info "Skipped Homebrew cache deletion."
    fi
  else
    ok "Homebrew cache folder not found."
  fi
}

docker_daemon_running() {
  # If docker exists and docker info works, daemon is running
  if ! need_cmd docker; then
    return 1
  fi
  docker info >/dev/null 2>&1
}

task_docker_prune() {
  section "Docker prune"
  if ! need_cmd docker; then
    warn "docker CLI not found. Skipping."
    return 0
  fi

  if ! docker_daemon_running; then
    warn "Docker daemon does not appear to be running."
    info "If you want to prune, start Docker Desktop first, then rerun:"
    echo "  open -a Docker"
    echo "  $SCRIPT_NAME --only docker-prune"
    return 0
  fi

  warn "This removes stopped containers, unused networks, dangling images, and build cache."
  if confirm "Run safe prune: docker system prune ?"; then
    run "docker system prune"
    ok "Docker prune complete."
  else
    info "Skipped Docker prune."
  fi
}

task_spotlight() {
  section "Spotlight reindex"
  if ! need_cmd mdutil; then
    warn "mdutil not found. Skipping."
    return 0
  fi

  warn "This can spike CPU and fans. Best done overnight."
  if confirm "Reindex Spotlight with 'sudo mdutil -E /' ?"; then
    run "sudo mdutil -E /"
    ok "Spotlight reindex triggered."
  else
    info "Skipped Spotlight reindex."
  fi
}

# ---------- selection logic ----------
ASSUME_YES=0
DRY_RUN=0
ONLY_SET=()
SKIP_SET=()
TASKS_RAN=()
TASKS_SKIPPED=()

list_tasks() {
  echo "Available tasks:"
  for k in "${DEFAULT_ORDER[@]}"; do
    printf "  %-16s %s\n" "$k" "$(task_desc "$k")"
  done
  echo
  echo "Examples:"
  echo "  $SCRIPT_NAME                  # prompt through all tasks"
  echo "  $SCRIPT_NAME --yes            # run all tasks without prompts"
  echo "  $SCRIPT_NAME --dry-run        # show what would run"
  echo "  $SCRIPT_NAME --only xcode-deriveddata,tm-snapshots"
  echo "  $SCRIPT_NAME --skip spotlight,docker-prune"
}

parse_csv() {
  local csv="$1"
  IFS=',' read -r -a arr <<< "$csv"
  for i in "${arr[@]}"; do
    # trim whitespace
    i="$(echo "$i" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$i" ]] && echo "$i"
  done
}

validate_task() {
  local t="$1"
  if [[ -z "$(task_desc "$t")" ]]; then
    err "Unknown task: $t"
    err "Run: $SCRIPT_NAME --list"
    exit 2
  fi
}

should_run_task() {
  local t="$1"

  # If ONLY_SET specified, run only those.
  if [[ "${#ONLY_SET[@]}" -gt 0 ]]; then
    for o in "${ONLY_SET[@]}"; do
      [[ "$t" == "$o" ]] && return 0
    done
    return 1
  fi

  # Otherwise, skip if in SKIP_SET
  for s in "${SKIP_SET[@]}"; do
    [[ "$t" == "$s" ]] && return 1
  done
  return 0
}

usage() {
  cat <<EOF
$SCRIPT_NAME - quarterly dev cleanup helper

Usage:
  $SCRIPT_NAME [options]

Options:
  --list                 List available tasks
  --only <csv>           Run only specified tasks (comma-separated)
  --skip <csv>           Skip specified tasks (comma-separated)
  --yes                  Run without interactive prompts (auto-yes)
  --dry-run              Print commands without executing
  -h, --help             Show help

EOF
}

# ---------- args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) list_tasks; exit 0 ;;
    --only)
      [[ $# -ge 2 ]] || { err "--only requires a CSV list"; exit 2; }
      while read -r t; do validate_task "$t"; ONLY_SET+=("$t"); done < <(parse_csv "$2")
      shift 2
      ;;
    --skip)
      [[ $# -ge 2 ]] || { err "--skip requires a CSV list"; exit 2; }
      while read -r t; do validate_task "$t"; SKIP_SET+=("$t"); done < <(parse_csv "$2")
      shift 2
      ;;
    --yes) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

# ---------- run ----------
info "Starting $SCRIPT_NAME"
info "Disk: $(bytes_free_human)"
[[ "$DRY_RUN" == "1" ]] && warn "Dry-run mode enabled."
[[ "$ASSUME_YES" == "1" ]] && warn "Auto-yes enabled. No prompts."

for t in "${DEFAULT_ORDER[@]}"; do
  validate_task "$t"
  if should_run_task "$t"; then
    "$(task_fn "$t")"
    TASKS_RAN+=("$t")
  else
    info "Skipping task: $t"
    TASKS_SKIPPED+=("$t")
  fi
done

echo
echo "$(color 1 '=== Summary ===')"
if [[ "${#TASKS_RAN[@]}" -gt 0 ]]; then
  echo "$(color 32 '  Ran:')     ${TASKS_RAN[*]}"
fi
if [[ "${#TASKS_SKIPPED[@]}" -gt 0 ]]; then
  echo "$(color 90 '  Skipped:') ${TASKS_SKIPPED[*]}"
fi
echo
ok "All done."
info "Disk: $(bytes_free_human)"
info "Tip: Storage numbers may update after a reboot."