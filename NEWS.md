# vpro 0.0.0.9000

* SU lifecycle APIs now inspect, attach, activate, deactivate, recover, safely detach, and transactionally save independent site-unit tables while preserving shared SQLite attachments.
* Project lifecycle APIs now inspect and attach VP08 SQLite projects, activate coordinator-scoped compatibility views, guard detach operations, and transactionally save a project under a new name.
* `vpro_project_recover()` restores the configured current project at startup and falls back to an explicit Sample database when recovery fails.
* `run_vpro()` now launches the packaged application explicitly; attaching the package no longer starts Shiny or modifies the installed `bslib` package.
* `vpro_install()`, `vpro_data_install()`, and `vpro_config_install()` initialize user-owned storage without replacing existing files by default.
* `vpro_config_get()` and `vpro_config_set()` provide a YAML-backed replacement for settings historically stored in the Windows registry.
