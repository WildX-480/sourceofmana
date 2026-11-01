BEGIN TRANSACTION;

DROP TRIGGER IF EXISTS trg_account_delete;
DROP TRIGGER IF EXISTS trg_character_delete;

CREATE TABLE item_new (
    item_id     INTEGER NOT NULL,
    char_id     INTEGER NOT NULL,
    count       INTEGER NOT NULL,
    storage     INTEGER NOT NULL CHECK(storage IN (0, 1)),
    customfield TEXT NOT NULL,
    PRIMARY KEY (char_id, item_id, storage, customfield),
    FOREIGN KEY (char_id) REFERENCES character(char_id)
) WITHOUT ROWID;

INSERT INTO item_new (item_id, char_id, count, storage, customfield)
SELECT item_id, char_id, count, storage, customfield
FROM item
WHERE char_id IN (SELECT char_id FROM character);

DROP TABLE item;
ALTER TABLE item_new RENAME TO item;

CREATE TABLE quest_new (
    char_id              INTEGER NOT NULL,
    quest_id             INTEGER NOT NULL,
    state                INTEGER NOT NULL,
    PRIMARY KEY (char_id, quest_id),
    FOREIGN KEY (char_id) REFERENCES character(char_id)
) WITHOUT ROWID;

INSERT INTO quest_new (char_id, quest_id, state)
SELECT char_id, quest_id, state
FROM quest
WHERE char_id IN (SELECT char_id FROM character);

DROP TABLE quest;
ALTER TABLE quest_new RENAME TO quest;

CREATE TABLE skill_new (
    char_id              INTEGER NOT NULL,
    skill_id             INTEGER NOT NULL,
    level                INTEGER,
    PRIMARY KEY (char_id, skill_id),
    FOREIGN KEY (char_id) REFERENCES character(char_id)
) WITHOUT ROWID;

INSERT INTO skill_new (char_id, skill_id, level)
SELECT char_id, skill_id, level
FROM skill
WHERE char_id IN (SELECT char_id FROM character);

DROP TABLE skill;
ALTER TABLE skill_new RENAME TO skill;

CREATE TABLE bestiary_new (
    char_id              INTEGER NOT NULL,
    mob_id               INTEGER NOT NULL,
    killed_count         INTEGER DEFAULT 0,
    PRIMARY KEY (char_id, mob_id),
    FOREIGN KEY (char_id) REFERENCES character(char_id)
) WITHOUT ROWID;

INSERT INTO bestiary_new (char_id, mob_id, killed_count)
SELECT char_id, mob_id, killed_count
FROM bestiary
WHERE char_id IN (SELECT char_id FROM character);

DROP TABLE bestiary;
ALTER TABLE bestiary_new RENAME TO bestiary;

DELETE FROM auth_token WHERE account_id NOT IN (SELECT account_id FROM account);

CREATE TRIGGER trg_account_delete
AFTER DELETE ON account
FOR EACH ROW
BEGIN
    DELETE FROM character WHERE account_id = OLD.account_id;
    DELETE FROM auth_token WHERE account_id = OLD.account_id;
END;

CREATE TRIGGER trg_character_delete
AFTER DELETE ON character
FOR EACH ROW
BEGIN
    DELETE FROM trait WHERE char_id = OLD.char_id;
    DELETE FROM attribute WHERE char_id = OLD.char_id;
    DELETE FROM stat WHERE char_id = OLD.char_id;
    DELETE FROM equipment WHERE char_id = OLD.char_id;
    DELETE FROM item WHERE char_id = OLD.char_id;
    DELETE FROM quest WHERE char_id = OLD.char_id;
    DELETE FROM skill WHERE char_id = OLD.char_id;
    DELETE FROM bestiary WHERE char_id = OLD.char_id;
END;

CREATE INDEX IF NOT EXISTS idx_character_account ON character(account_id);

COMMIT;
