# Sentry for Cursor

The Sentry plugin for Cursor. It teaches Cursor how to use Sentry: SDK setup
wizards for any platform, production issue debugging via the Sentry MCP server,
code review with Sentry context, and monitoring configuration.

> [!IMPORTANT]
> This branch is generated. It is built from the `main` branch of
> [getsentry/sentry-for-ai](https://github.com/getsentry/sentry-for-ai) and
> includes every skill in that library. Do not edit files here; make changes on
> `main` and they will be rebuilt into this branch.

## Install

Add `getsentry/sentry-for-ai` with the `dist-cursor` branch from Cursor
Settings > Plugins.

## What's included

- The full Sentry skill library (SDK setup wizards, debugging and code-review
  workflows, feature setup).
- The `/seer` command for natural-language Sentry queries.
- The hosted [Sentry MCP server](https://mcp.sentry.dev) for querying your
  Sentry environment.
