# Dev Cleanup Script (macOS)

A safe, interactive cleanup script for macOS developers who want to reclaim disk space **without breaking their environment**.

This script is designed for **quarterly cleanup**, post–big-project cleanup, or whenever macOS starts reporting large amounts of mysterious "System Data".

---

## Why this exists

Modern dev machines accumulate a lot of **regeneratable junk**:

* Xcode build artifacts
* iOS simulators
* Node / Expo / Metro caches
* Docker images and build cache
* Logs and local Time Machine snapshots

Most guides online either:

* Tell you to delete everything blindly, or
* Give you one-off commands you forget later

This script gives you:

* Guardrails
* Explanations
* Opt-in cleanup, one category at a time

---

## What this script does

* Walks through common dev-related disk hogs
* Shows you disk usage before deleting
* Asks before every destructive action
* Supports flags for targeted or automated runs

It **only deletes regeneratable data**. Your repos and personal files are never touched.

---

## Installation

1. Save the script as one of the following:

   * `cleanup.sh`
   * `dev-cleanup.sh`
   * `quarterly-cleanup.sh`

2. Make it executable:

```bash
chmod +x cleanup.sh
```

3. Run it:

```bash
./cleanup.sh
```

Optional but recommended: move it somewhere permanent, for example `~/scripts/`, and add an alias:

```bash
alias dev-cleanup="~/scripts/cleanup.sh"
```

---

## Common use cases

### Interactive quarterly cleanup (recommended)

```bash
./cleanup.sh
```

You will be prompted for each cleanup step.

---

### See what the script can do

```bash
./cleanup.sh --list
```

---

### Run only specific cleanups

```bash
./cleanup.sh --only xcode-deriveddata,ios-simulators
```

Useful after Xcode updates or iOS-heavy work.

---

### Skip things you do not want to touch

```bash
./cleanup.sh --skip docker-prune,spotlight
```

---

### Non-interactive mode (advanced)

```bash
./cleanup.sh --yes
```

Runs all selected tasks without prompting. Use with care.

---

### Dry run (safe preview)

```bash
./cleanup.sh --dry-run
```

Shows what *would* be deleted without deleting anything.

---

## Cleanup tasks included

| Task              | Description                                 |
| ----------------- | ------------------------------------------- |
| report            | Shows disk usage for common dev directories |
| xcode-deriveddata | Clears Xcode build artifacts                |
| ios-simulators    | Removes unused or all iOS simulators        |
| node-caches       | Clears npm, Expo, Metro caches              |
| tm-snapshots      | Thins local Time Machine snapshots          |
| logs              | Clears user and system logs                 |
| homebrew          | Removes old Homebrew versions and cache     |
| docker-prune      | Safe Docker cleanup (no volumes)            |
| spotlight         | Reindexes Spotlight (rarely needed)         |

---

## Docker philosophy (important)

This script assumes Docker should be:

* Installed
* **Not always running**
* Cleaned only when needed

Docker-related cleanup **only runs if the Docker daemon is running**. Nothing is force-started.

---

## Adding a new cleanup task

1. Add a description:

```bash
TASK_DESC["my-task"]="What this cleanup does"
TASK_FN["my-task"]="task_my_task"
```

2. Add it to the execution order:

```bash
DEFAULT_ORDER+=("my-task")
```

3. Implement the function:

```bash
task_my_task() {
  section "My Task"
  if confirm "Run my cleanup?"; then
    run "echo doing cleanup"
  fi
}
```

The script will automatically support `--only my-task` and `--skip my-task`.

---

## Removing a cleanup task

* Remove it from `TASK_DESC`
* Remove it from `TASK_FN`
* Remove it from `DEFAULT_ORDER`

No other changes required.

---

## Safety notes

* Always close Xcode, Simulators, and Docker Desktop before running
* Expect first builds after cleanup to be slower
* Disk usage numbers may update after a reboot

---

## Recommended cadence

* **Quarterly**: Full interactive run
* **After big projects**: Xcode, Node, Docker only
* **Low disk emergency**: Report → targeted cleanup

---

## License / Usage

Use freely, modify aggressively, and adapt it to your workflow.

This script reflects a pragmatic developer mindset:

> Keep your machine clean, but never at the cost of productivity.
