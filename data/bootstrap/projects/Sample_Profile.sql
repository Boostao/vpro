-- Access table description: VP05-2
CREATE TABLE "Profile" (
  "Order" SMALLINT,
  "Table" VARCHAR,
  "Field" VARCHAR,
  "Operator" VARCHAR,
  "Layer" VARCHAR,
  "Species" VARCHAR,
  "Criteria" VARCHAR,
  "Operation" VARCHAR,
  "PlotCount" INTEGER
);

/*
Access metadata notes for Profile:
- Table Description: VP05-2
- Access exported no explicit validation rules or relationships for this table.
Potential write constraints to consider later:
- CHECK(length("Table") <= 255)
- CHECK(length("Field") <= 255)
*/
