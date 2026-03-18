# VPRO Sync Logic Reference

Complete documentation of the bidirectional sync engine for syncing field DuckDB with master PostgreSQL database.

## Overview

Field users work offline with a local **DuckDB** database. A cloud **PostgreSQL** holds the authoritative master copy. The sync engine supports:
- **Pull** (master → local): Download env/SU/Veg updates + reference lists from master
- **Push** (local → staging → admin review → master): Upload local changes to staging, admin reviews conflicts, approves merge
- **Conflict detection & resolution**: Pull conflicts on client, server-side merge conflicts at review
- **List sync** (admin-only): Reference lists (species codes, BEC zones, etc.) are read-only for users; admins update on master, field users get fresh copy on next sync_pull

---

## Architecture

```mermaid
graph TB
    subgraph LocalEnv["🏕️ Field User (Local)"]
        DuckDB["Local DuckDB<br/>Env, SU, Veg<br/>+ sync.watermarks<br/>+ sync.conflict_queue"]
        Lists["Local lists catalog<br/>(USysTableOfLists,<br/>USysZoneList, etc.)"]
    end
    
    subgraph CloudEnv["☁️ Cloud Master"]
        PG["PostgreSQL Master<br/>core. (Env, SU, Veg)<br/>staging. (env_staged, su_staged, veg_staged)<br/>admin. (merge_requests, merge_conflicts)<br/>lists. (reference tables)"]
    end
    
    DuckDB -->|ATTACH| PG
    Lists -->|ATTACH| PG
    DuckDB -->|sync_pull| PG
    Lists -->|sync_pull (full replace)| PG
    DuckDB -->|sync_push| PG
    PG -->|admin review| Admin["Admin Interface<br/>merge_approve_request<br/>merge_reject_request"]
    Admin -->|apply merge| PG
```

---

## Data Flow Diagram: Complete Sync Cycle

```mermaid
sequenceDiagram
    participant User as Field User
    participant Local as Local DuckDB
    participant Staging as PG Staging<br/>Tables
    participant Core as PG Core<br/>Tables
    participant Admin as Admin Review
    
    User->>Local: Edit Env/SU/Veg offline
    User->>Local: sync_pull() [includes lists if attached]
    
    rect rgb(200, 220, 255)
        Note over User,Core: PULL PHASE: Data Tables (sync_pull)
    end
    Local->>Core: Query Env/SU/Veg changed rows<br/>(since last_pull_utc watermark)
    Core-->>Local: Return rows
    Note over Local: Compare master_row_version<br/>& values; detect conflicts
    alt No conflict
        Local->>Local: Fast-forward row<br/>Update master_row_version
    else Conflict detected
        Local->>Local: Queue to<br/>sync.conflict_queue
    end
    Local->>Local: Set last_pull_utc watermark
    
    rect rgb(230, 200, 255)
        Note over User,Core: PULL PHASE: Lists (sync_pull lists=TRUE)
    end
    Note over Local: If lists catalog attached<br/>(lists is read-only, field users<br/>never edit)
    Local->>Core: Query all rows from<br/>master.lists.*
    Core-->>Local: Return full table contents
    Note over Local: DELETE old rows<br/>INSERT master rows<br/>(full replace, no conflict)
    Local->>Local: Set lists watermark
    
    rect rgb(200, 255, 220)
        Note over User,Core: PUSH PHASE (sync_push)
    end
    User->>Local: Resolve pull conflicts<br/>(if any)
    User->>Local: sync_push()
    Note over Local: Guard: abort if<br/>unresolved pull conflicts
    Local->>Local: Find changed rows<br/>(LEFT JOIN master.core)
    Local->>Staging: INSERT to staging tables<br/>set base_row_version,<br/>change_type='I'|'U'
    Note over Staging: Creates merge_request
    Local->>Local: Set last_push_utc watermark
    
    rect rgb(255, 240, 200)
        Note over Admin,Core: ADMIN REVIEW PHASE (merge_request_*)
    end
    Admin->>Staging: merge_request_list()
    Admin->>Staging: merge_request_refresh_conflicts()
    Note over Staging: Detect row_version mismatch<br/>core.row_version ><br/>staging.base_row_version
    alt Conflicts found
        Admin->>Staging: merge_request_get_conflicts()
        Admin->>Staging: merge_request_resolve_conflict()<br/>(keep_staged|keep_core|dismiss)
    else No conflicts
        Note over Admin: Ready to approve
    end
    
    rect rgb(255, 200, 200)
        Note over Admin,Core: MERGE PHASE (merge_approve_request)
    end
    Admin->>Staging: merge_approve_request()
    Staging->>Core: APPLY: INSERT/UPDATE core tables<br/>respecting resolved conflicts
    Note over Core: Triggers auto-increment row_version
    Core->>Staging: DELETE staging rows
    Note over Staging: mark merge_request status='merged'
```

---

## Lists Sync

**Reference lists** (`USysTableOfLists`, `USysZoneList`, `USysSppAttributes`, etc.) are admin-only data sources. Field users never edit them—they are used for dropdowns, validation, and reference lookups.

### How It Works

When `sync_pull(con, tables = c("env", "su", "veg", "lists"))` is called:

1. **Local lists catalog must be attached** as `lists` from the canonical SQLite store (for example `ATTACH 'data/VLists.db' AS lists (TYPE SQLITE)`).
2. For each table in the local `lists` catalog:
   - Look for a matching table in `master.lists.*` (case-insensitive match).
   - If found, **DELETE all rows from local** then **INSERT all rows from master**.
   - If not found, **skip** and record in `$skipped`.
3. **No conflict detection** — lists are authoritative on master; local is always overwritten.
4. A watermark for `"lists"` is recorded to track the last sync time.

### Return Value

```r
result$lists
  $synced_tables  # (integer) count of tables successfully synced
  $skipped        # (character vector) tables in local but not in master
```

### Example

```r
con <- connect_local_db()  # opens the runtime DuckDB session with canonical SQLite databases attached
result <- sync_pull(con, tables = c("env", "su", "veg", "lists"))
print(result$lists)  # e.g., list(synced_tables = 14L, skipped = character(0))
```

### No Watermark-Based Filtering

Unlike Env/SU/Veg pulls (which use `last_pull_utc` to fetch only changed rows), lists are always **fully replaced**. This is fine because:
- Lists are small (typically < 10K rows).
- Admin adds/updates are infrequent.
- No user edits → no push conflicts.
- Simplifies sync logic (no need to track which list items changed).
