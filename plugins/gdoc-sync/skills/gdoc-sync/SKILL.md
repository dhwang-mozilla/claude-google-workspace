---
name: gdoc-sync
description: Pull a Google Doc to a local file and push local edits back, via the `gws` Google Workspace CLI authed off an existing `gcloud auth login` (no GCP project or service-account key needed). Invoke when the user wants to download/export a Google Doc, edit it locally and push it back, sync a Doc with a local markdown/text file, or set up gws auth without self-provisioning credentials.
---

# gdoc-sync

Pull/push a Google Doc against a local file using the `gws` CLI ([googleworkspace/cli](https://github.com/googleworkspace/cli)). Auth is derived from the user's interactive `gcloud` login, sidestepping the org policy that blocks self-provisioning GCP projects / service-account keys.

## When to invoke

- "download / export this Google Doc"
- "edit this doc locally and push it back"
- "sync this doc with a markdown file"
- "set up the Google Workspace CLI" / "gws needs creds"

## One-time auth

The user cannot run `gws auth setup` (it needs create-project rights blocked by org policy). Instead, auth off the existing gcloud login:

```bash
gcloud auth login --enable-gdrive-access   # browser consent, adds the Drive scope
```

The helper script mints a fresh token (`gcloud auth print-access-token`) on every call, so the ~1h token expiry and per-shell `GOOGLE_WORKSPACE_CLI_TOKEN` are handled automatically — no manual re-export.

For scopes beyond Drive (Gmail/Calendar), use ADC instead: `gcloud auth application-default login --scopes=<csv>` + `gcloud auth application-default print-access-token` (swap that into `refresh_token` in `gdoc.sh`). For a persistent, full-scope, auto-refreshing credential, the real fix is a shared OAuth client (`GOOGLE_WORKSPACE_CLI_CLIENT_ID`/`_SECRET` + `gws auth login`), which needs someone with create rights to hand over a client id/secret.

## Usage

The script ships with this plugin; invoke it via the `${CLAUDE_PLUGIN_ROOT}` env var (exported into the shell when the plugin runs):

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/gdoc-sync/gdoc.sh" find <name-substring>                       # search Docs by name -> id + title
"${CLAUDE_PLUGIN_ROOT}/skills/gdoc-sync/gdoc.sh" pull <doc-id-or-url> <output-file> [mime]   # default mime: text/markdown
"${CLAUDE_PLUGIN_ROOT}/skills/gdoc-sync/gdoc.sh" push <doc-id-or-url> <local-file>  [mime]
"${CLAUDE_PLUGIN_ROOT}/skills/gdoc-sync/gdoc.sh" name <doc-id-or-url>
```

`find` searches by name substring so you don't have to copy/paste IDs — `find` to get the id, then `pull`/`push` with it. Uses the Drive `files.list` `q` syntax (string literals in single quotes, `and`/`or`, `name contains`, `mimeType=`, `trashed=false`).

Accepts a bare file ID or a full `docs.google.com/document/d/<ID>/edit` URL.

Common export mimes (Docs): `text/markdown`, `text/plain`, `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document` (docx). `text/csv` only works on a **Sheet**, not a Doc.

## Critical caveats (verified empirically)

- **`push` is a full-content REPLACE, not a merge.** It rebuilds the entire doc body from the uploaded file. Whatever you push becomes the whole document.
- **It orphans anchored comments.** The upload assigns new internal element IDs, so every comment anchor detaches — even where the text string is identical. Comments survive as objects (readable via `gws drive comments list`) but unpin in the browser. To preserve anchored comments you must edit surgically via Docs `documents.batchUpdate` (`insertText` / `replaceAllText` / `deleteContentRange`) instead — this skill does not do that.
- **Concurrency:** don't let anyone edit the live doc between `pull` and `push` — their changes get overwritten (recoverable via File > Version history, but still).
- **Markdown round-trips are lossy** (formatting normalizes). Treat one side as the source of truth and sync one-way.

## Recommended flow

`pull` → edit locally → `push`. Safe for docs the user owns and regenerates from a local source, where comment anchoring doesn't need to survive.
