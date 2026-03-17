CREATE TABLE "tblMessageList" (
  "ID" INTEGER PRIMARY KEY,
  "MessageID" INTEGER UNIQUE,
  "Read" BOOLEAN DEFAULT FALSE
);

/*
Access notes:
- ID used GenUniqueID() in Access; SQLite uses INTEGER PRIMARY KEY and preserves imported IDs.
- MessageID is unique in Access and is used by qryAddToMessageList to sync from tblMessageBoard.ID.
- Existing Access data contains unmatched MessageID values, so this is not enforced as a foreign key in SQLite.
- Read defaults to false for newly inserted message-list rows.
*/

