# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add first-class Codex adapters and lifecycle hooks alongside Claude Code's
  canonical project contract and workflows.
- Add shared, agent-neutral scripts while keeping Claude Code as the native host.

## [0.1.0] - 2026-08-21

### Breaking Changes

- Replace the generated-template publishing flow with direct framework development
  and the `sync_framework.sh` update, diff, and export workflow.

### Added

- Add safe framework synchronization between published templates and private vaults.
- Add session hot-cache enforcement and content-only local auto-commits.
- Add separate GitHub-backed and local-only setup paths.

### Fixed

- Restrict framework exports to files tracked by the destination template.
- Make ingest and save workflows inherit the vault language convention.

[Unreleased]: https://github.com/sturlese/hippocampus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sturlese/hippocampus/releases/tag/v0.1.0
