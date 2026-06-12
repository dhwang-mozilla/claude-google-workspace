# claude-google-workspace

A [Claude Code](https://code.claude.com) plugin marketplace with skills for Google Workspace.

## Plugins

| Plugin | What it does |
| --- | --- |
| `gdoc-sync` | Pull a Google Doc to a local file and push local edits back, via the [`gws`](https://github.com/googleworkspace/cli) CLI — authed off your existing `gcloud` login, no GCP project or service-account key needed. |

## Install

In Claude Code:

```bash
/plugin marketplace add dhwang-mozilla/claude-google-workspace
/plugin install gdoc-sync@claude-google-workspace
```

## Prerequisites

- [`gcloud`](https://cloud.google.com/sdk/docs/install) and [`gws`](https://github.com/googleworkspace/cli) on your `PATH`.
- One-time auth (browser consent, adds the Drive scope):
  ```bash
  gcloud auth login --enable-gdrive-access
  ```

The skill mints a fresh access token from your gcloud login on every call, so there's nothing else to configure.

## Usage

Once installed, the `gdoc-sync` skill triggers automatically on Google-Doc requests ("download this doc", "sync this doc with a local file", etc.). You can also call the bundled script directly — see `plugins/gdoc-sync/skills/gdoc-sync/SKILL.md` for the full command reference and important caveats (notably: `push` is a full-content replace and orphans anchored comments).
