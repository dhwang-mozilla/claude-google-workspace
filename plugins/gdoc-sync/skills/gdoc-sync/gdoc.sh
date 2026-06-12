#!/usr/bin/env bash
# gdoc — pull/push a Google Doc <-> local file via the `gws` CLI.
# Auth: derives a fresh access token from your existing `gcloud auth login`
# (run once: `gcloud auth login --enable-gdrive-access`). No GCP project / SA key needed.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

# Accepts a bare ID or a full docs.google.com/.../d/<ID>/... URL (docs, sheets, slides).
parse_id() {
  local in="$1"
  if [[ "$in" =~ /d/([a-zA-Z0-9_-]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$in"
  fi
}

refresh_token() {
  command -v gws >/dev/null   || die "gws not on PATH"
  command -v gcloud >/dev/null || die "gcloud not on PATH"
  GOOGLE_WORKSPACE_CLI_TOKEN="$(gcloud auth print-access-token 2>/dev/null)" \
    || die "could not mint token — run: gcloud auth login --enable-gdrive-access"
  export GOOGLE_WORKSPACE_CLI_TOKEN
}

# Map a friendly type alias to a Drive mimeType (empty -> any type).
type_mime() {
  case "$1" in
    doc)    echo "application/vnd.google-apps.document" ;;
    sheet)  echo "application/vnd.google-apps.spreadsheet" ;;
    slide)  echo "application/vnd.google-apps.presentation" ;;
    folder) echo "application/vnd.google-apps.folder" ;;
    "")     echo "" ;;
    *)      die "unknown --type '$1' (use doc|sheet|slide|folder)" ;;
  esac
}

# Guardrail: refuse to mutate a file you don't own unless --force is passed.
# Compares the active gcloud account against the file's Drive owners.
assert_owner_or_force() {
  local id="$1" force="$2" me info owner
  me="$(gcloud config get-value account 2>/dev/null)" || die "cannot determine active gcloud account"
  info="$(gws drive files get --params "{\"fileId\":\"$id\",\"fields\":\"name,owners(displayName,emailAddress)\",\"supportsAllDrives\":true}" 2>/dev/null)" \
    || die "could not fetch metadata for $id (check the id and that you can access it)"
  if printf '%s' "$info" | grep -qF "\"$me\""; then
    return 0   # you are an owner — proceed
  fi
  owner="$(printf '%s' "$info" | grep -o '"emailAddress"[^,}]*' | head -1 | grep -o '[^"]*@[^"]*')"
  if [[ "$force" == "1" ]]; then
    # --force does not auto-proceed: require an explicit typed confirmation at the terminal.
    [[ -e /dev/tty ]] || die "GUARDRAIL — you ($me) do not own $id (owner: ${owner:-unknown}); --force needs an interactive terminal to confirm. Aborting."
    echo "WARNING: you ($me) do NOT own $id (owner: ${owner:-unknown})." >&2
    printf "Override the ownership guardrail and overwrite it? Type 'yes' to proceed: " >&2
    read -r ans < /dev/tty || ans=""
    [[ "$ans" == "yes" ]] || die "aborted — override not confirmed (you typed: '${ans}')."
    echo "override confirmed." >&2
    return 0
  fi
  die "GUARDRAIL — refusing to modify $id: you ($me) are not an owner (owner: ${owner:-unknown}).
       This protects against editing/overwriting artifacts you don't own.
       If you are certain, re-run with --force (you will be asked to confirm)."
}

usage() {
  cat >&2 <<'EOF'
usage:
  gdoc pull <id-or-url> <output-file> [mime]    # export a Doc/Sheet/Slide -> local (default mime: text/markdown)
  gdoc push <id-or-url> <local-file>  [mime] [--force]
                                                # replace a file's body with local file (OWNERSHIP-GUARDED)
  gdoc find <name-substring> [--type doc|sheet|slide|folder] [--shared]
                                                # search by name across ALL file types + shared drives
  gdoc name <id-or-url>                         # print the file's title

notes:
  - push is a FULL-CONTENT REPLACE: it overwrites the whole doc body and orphans anchored comments.
    Old versions remain in File > Version history. Don't let others edit the live doc between pull and push.
  - push refuses files you don't own unless you pass --force. This guardrail is the only write path on purpose.
  - find/pull/name are read-only. find searches all file types and includes shared drives.
EOF
  exit 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  pull)
    # gws sandboxes --output to the cwd, so cd into the target dir and use the basename.
    [[ $# -ge 2 ]] || usage
    id="$(parse_id "$1")"; out="$2"; mime="${3:-text/markdown}"
    outdir="$(cd "$(dirname "$out")" && pwd)" || die "no such dir: $(dirname "$out")"
    refresh_token
    ( cd "$outdir" && gws drive files export --params "{\"fileId\":\"$id\",\"mimeType\":\"$mime\"}" -o "$(basename "$out")" )
    echo "pulled $id -> $outdir/$(basename "$out") ($mime)" >&2
    ;;
  push)
    # gws sandboxes --upload to the cwd, so cd into the file's dir and use the basename.
    # Strip an optional --force flag from anywhere in the args.
    force=0; pos=()
    for a in "$@"; do [[ "$a" == "--force" ]] && force=1 || pos+=("$a"); done
    set -- "${pos[@]}"
    [[ $# -ge 2 ]] || usage
    id="$(parse_id "$1")"; file="$2"; mime="${3:-text/markdown}"
    [[ -f "$file" ]] || die "no such file: $file"
    filedir="$(cd "$(dirname "$file")" && pwd)"
    refresh_token
    assert_owner_or_force "$id" "$force"
    ( cd "$filedir" && gws drive files update --params "{\"fileId\":\"$id\",\"supportsAllDrives\":true}" --upload "$(basename "$file")" --upload-content-type "$mime" )
    echo "pushed $file -> $id (full-content replace)" >&2
    ;;
  name)
    [[ $# -ge 1 ]] || usage
    id="$(parse_id "$1")"
    refresh_token
    gws drive files get --params "{\"fileId\":\"$id\",\"fields\":\"name\",\"supportsAllDrives\":true}"
    ;;
  find)
    # Search by name substring across ALL file types and shared drives.
    # Optional: --type <doc|sheet|slide|folder> to filter; --shared to restrict to shared-with-me.
    type=""; shared=0; terms=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)   type="${2:-}"; shift 2 ;;
        --shared) shared=1; shift ;;
        *)        terms+=("$1"); shift ;;
      esac
    done
    [[ ${#terms[@]} -ge 1 ]] || usage
    q="name contains '${terms[*]}' and trashed=false"
    mime="$(type_mime "$type")"
    [[ -n "$mime" ]] && q="$q and mimeType='$mime'"
    [[ "$shared" == "1" ]] && q="$q and sharedWithMe"
    refresh_token
    gws drive files list --params "{\"q\":\"$q\",\"fields\":\"files(id,name,mimeType,modifiedTime,owners(displayName))\",\"orderBy\":\"modifiedTime desc\",\"pageSize\":25,\"includeItemsFromAllDrives\":true,\"supportsAllDrives\":true,\"corpora\":\"allDrives\"}"
    ;;
  *)
    usage
    ;;
esac
