CREATE TRIGGER "trg_tblMessageBoard_add_to_message_list"
AFTER INSERT ON "tblMessageBoard"
FOR EACH ROW
WHEN NEW."ID" IS NOT NULL
 AND NOT EXISTS (
   SELECT 1
   FROM "tblMessageList"
   WHERE "MessageID" = NEW."ID"
 )
BEGIN
  INSERT INTO "tblMessageList" ("MessageID")
  VALUES (NEW."ID");
END;