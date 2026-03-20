CREATE TABLE "CodesToReplace" (
  "Current code" TEXT,
  "New code" TEXT
);

CREATE INDEX "idx_CodesToReplace_Current_code" ON "CodesToReplace" ("Current code");
CREATE INDEX "idx_CodesToReplace_New_code" ON "CodesToReplace" ("New code");
