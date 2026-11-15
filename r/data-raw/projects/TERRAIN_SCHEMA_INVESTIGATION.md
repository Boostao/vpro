# Terrain field-size evidence and read-only diagnostic

## Access evidence

`V7mdlTerrain.TestTerrainFieldSize` checks only `SurfaceExpSurf.Size = 3` on a linked project Env table. It returns false for `Sample_Env` without checking its schema. `SetTerrainFieldSize` has no discovered production caller in the exported text; private `DoIt` invokes it. The procedure asks for confirmation, disables Access warnings, pauses at `Stop`, and recreates eight fields in sequence, targeting 3 characters for six fields and 6 for the two surficial-material fields. Its primary error-handler declaration is commented out. No atomicity or rollback is established by this source; do not port the mutation as-is.

The VP05, VP06, and VP07 import modules map terrain fields into newer projects, but those mappings do not record source field widths or prove the field-resizing routine ran. Read-only `mdb-schema` inspection of unmodified bundled template files at `../VPRO_ACCESS/VPro64/Templates/` found:

| Template / Env table | Texture | Surficial material | Surface exposure | Geomorphic process |
| --- | ---: | ---: | ---: | ---: |
| `TemplateVProXP.mdb` / `VProXP_Env` | 3 | 6 | 3 | 6 |
| `TemplateVPro03.mdb` / `VPro03_Env` | 3 | 6 | 3 | 6 |
| `TemplateVPro13.accdb` / `VPro13_Env` | 3 | 6 | 3 | 3 |
| `TemplateVPro15.accdb` / `VPro15_Env` | 3 | 6 | 3 | 3 |
| `VPro64_forAI/Tables_Def/Sample_Env_CreateSQL.txt` | 3 | 6 | 3 | 3 |

Each number applies to both Surf and SubSurf fields. This is template evidence, not a census of projects or proof of version-to-width equivalence. Notably, applying the legacy resize target to an XP/03 template would **narrow** geomorphic process fields from 6 to 3. A prior claim that the legacy procedure simply enlarges all fields is unsupported by these templates. The templates do not establish how existing six-character values would be handled during that narrowing.

`data-raw/projects/Sample_Env.sql` and the bundled VP08 `Sample.db` instead declare all eight fields as unbounded `VARCHAR`. SQLite `_table_metadata` preserves the VP08 Env version but does not preserve Access terrain field widths. A SQLite numeric type argument is not a runtime length constraint.

## Diagnostic contract

`vpro_terrain_inspect_schema(path, project)` opens SQLite read-only and returns one row for each of the eight target fields with the legacy target width, normalized declared type, parsed declared width, and status. Statuses distinguish `match`, `undersized`, `oversized`, `unknown` (unbounded text), `non_text`, `missing_field`, and `missing_table`. Field lookup is case-insensitive. It reports the canonical Sample widths as unknown, not noncompliant, and intentionally does not skip Sample or change anything. The target widths are the legacy resize targets, not version-specific historical expectations or storage constraints. It is a broader intentional replacement for `TestTerrainFieldSize`; `SetTerrainFieldSize` and `DoIt` remain unmapped and unimplemented.

## Disposable project-copy value probe (2026-09-22)

Three candidate Access project files from `../VPRO_ACCESS/Vpro_data/` and the two XP/03 templates were copied to a temporary directory before inspection. `mdb-schema` and `mdb-export` read **only those copies**; the originals were not opened by the probe. The candidate names alone do not establish an XP/03/13/15 version. All three non-template Env tables declare both GeoMorPro fields `Text (3)`; the copied XP/03 templates declare `Text (6)` but contain zero Env rows. Code lengths below count nonempty exported cells (empty and null are not distinguished), not distinct codes:

| Copied source / Env table | Env rows | Surf nonempty | Surf lengths 1/2/3 | SubSurf nonempty | SubSurf lengths 1/2/3 | Values over 3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `BECMaster_fixing.accdb` / `BECMaster_fixing_Env` | 71,567 | 2,738 | 2,261 / 320 / 157 | 259 | 235 / 18 / 6 | 0 |
| `Haida_Gwaii_2019.accdb` / `Haida_Gwaii_VPro19_2019_Env` | 21 | 0 | 0 / 0 / 0 | 0 | 0 / 0 / 0 | 0 |
| `Manning_TEM_Vpro19.accdb` / `Manning_TEM_Vpro19_Env` | 61 | 5 | 4 / 1 / 0 | 2 | 2 / 0 / 0 | 0 |
| `TemplateVProXP.mdb` / `VProXP_Env` | 0 | 0 | 0 / 0 / 0 | 0 | 0 / 0 / 0 | 0 |
| `TemplateVPro03.mdb` / `VPro03_Env` | 0 | 0 | 0 / 0 / 0 | 0 | 0 / 0 / 0 | 0 |

The observed lack of values over 3 in **width-3 project fields** cannot establish whether historical width-6 projects contain longer codes. No populated historical width-6 project was found in the searched workspace.

**Decision (2026-09-22): Defer the terrain write-migration width policy until actual values from authorized, populated historical width-6 project copies are available.** Do not infer that narrowing to three characters is safe from empty templates or newer width-3 projects. Before designing a write migration, establish the affected source population and its actual values, choose how to preserve width-6 geomorphic codes, specify explicit backup and transactional replacement, and validate interruption recovery. No write operation is authorized by this diagnostic or probe.
