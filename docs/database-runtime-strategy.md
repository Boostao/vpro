# Database Runtime Strategy

## Current Canonical Local Storage

The migrated local VPro databases are now canonical SQLite files, not local DuckDB files.

- `data/VPro64.db` — main VPro companion database
- `data/VLists.db` — lists/reference database
- `data/VMetaData.db` — metadata database
- `data/VUser.db` — user/preferences database
- `data/VMessageBoard.db` — message board database
- `data/pics/VPics.db` — plot pictures database
- `data/projects/*.db` — per-project SQLite databases built from the `Sample_*` project tables

DuckDB remains part of the app architecture, but as a runtime query/composition layer rather than the persisted source of truth.

## Target App Runtime

At app boot, the intended runtime is:

1. Open an in-memory DuckDB connection.
2. Attach the canonical SQLite databases under stable aliases.
3. Create any runtime-only views that span multiple attached databases.
4. Run the Shiny app against that in-memory DuckDB session.

This keeps the canonical data editable with external SQLite tools such as SQLiteStudio, avoids committing to a single persistent local DuckDB file, and preserves better multi-client write possibilities than the earlier all-DuckDB local plan.

## Runtime-Only Cross-Database Queries

Two Access queries should be recreated at app boot in the in-memory DuckDB layer rather than stored inside individual SQLite files, because they span multiple attached databases:

- `MasterSiteUnitList`
- `MasterUnitList_Hierarchy`

Both currently resolve to the same Access SQL pattern:

```sql
SELECT *
FROM USysMasterSiteUnitList
UNION
SELECT *
FROM USysUserSiteUnitList;
```

In the new runtime, those references should be qualified against the attached SQLite aliases, for example `lists.USysMasterSiteUnitList` and `user.USysUserSiteUnitList`, or whatever final alias names the connection layer uses.

These are compatibility views for the app session. They are not canonical persisted tables and should not be treated as bootstrap targets for the individual SQLite databases.

## Documentation Rule

For future documentation, prompts, and migration notes:

- Treat the SQLite files under `data/` and `data/projects/` as the canonical local data stores.
- Treat in-memory DuckDB as the boot-time execution layer.
- Do not describe local `.duckdb` files as the canonical backend unless a document is explicitly historical.
- Keep PostgreSQL/cloud sync notes scoped to sync and cloud workflows; do not let them redefine the local canonical storage model.