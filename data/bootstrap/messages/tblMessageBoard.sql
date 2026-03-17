CREATE TABLE "tblMessageBoard" (
  "ID" INTEGER PRIMARY KEY,
  "TopicType" TEXT,
  "TopicDate" TEXT,
  "Audience" TEXT,
  "From" TEXT,
  "Title" TEXT,
  "Message" TEXT
);

/*
Access notes:
- ID used GenUniqueID() in Access; SQLite uses INTEGER PRIMARY KEY and preserves imported IDs.
- TopicDate is stored as text in the exported CSV/data path.
*/

