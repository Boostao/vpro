INSERT INTO "tblMessageList" ("MessageID")
SELECT "tblMessageBoard"."ID"
FROM "tblMessageBoard"
LEFT JOIN "tblMessageList"
  ON "tblMessageBoard"."ID" = "tblMessageList"."MessageID"
WHERE "tblMessageList"."MessageID" IS NULL;

/*
Equivalent to Access qryAddToMessageList:
- one-time sync adds any missing message IDs after bootstrap load
*/