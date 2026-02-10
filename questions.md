# BEC DATA MANAGEMENT 
What kind of governence is expected?
what kind of roles are expected? read only , read write + review needed?

## Access Parity Follow-ups
- Conductivity appears in Access VBA/modules/forms (site unit report summary + validation + import), but no exported table/CSV includes a Conductivity field. Do you have the source table or definition for Conductivity (or should we drop/derive it)?
- HumusPh and MineralPH are referenced in Access import/validation code but are not present in USysEnvTable or Sample_Env exports. Should we treat horizon pH fields (Sample_Humus.HumusFormpH and Sample_Mineral.MineralFormpH) as the canonical sources for site unit pH summaries, or is there another env-level source?

