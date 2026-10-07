import ballerina/sql;
import ballerinax/java.jdbc;

// ---------------------------------------------------------------------------
// SQLite persistence layer.
//
// The service keeps its data in a SQLite file (`library.db` by default) that it
// opens through the generic JDBC connector and the xerial `sqlite-jdbc` driver
// declared in Ballerina.toml. Data now survives a restart.
//
// Schema
//   institutions(institution_id PK, name UNIQUE, sites JSON)
//   assets(asset_tag PK, name, description, institution, site, status,
//          date_acquired, components JSON, schedules JSON, work_orders JSON,
//          current_loan JSON NULL)
//   id_sequence(name PK, value)        -- replaces the old in-memory counter
//
// Scalar fields that are searched or filtered on are real columns. The nested
// collections that always travel with their asset (components, schedules,
// work orders with their tasks, the current loan) are stored as JSON text.
//
// Every statement is a Ballerina parameterized query: values inside `${...}`
// are sent as bind parameters, never pasted into the SQL text, so the queries
// are safe from SQL injection.
//
// The pool is limited to one connection. SQLite allows only one writer at a
// time, so a single connection avoids "database is locked" errors. The
// `lock` blocks in store.bal make each read-modify-write sequence atomic.
// ---------------------------------------------------------------------------

# Path of the SQLite database file, relative to the working directory.
configurable string dbFile = "library.db";

# When `true`, every table is dropped and recreated on start-up (used by tests).
configurable boolean resetDatabase = false;

# Raised when the database itself fails (I/O error, corrupt row, ...).
# The service maps it to `500 Internal Server Error`.
public type StoreError distinct error;

final jdbc:Client db = check openDatabase();

function openDatabase() returns jdbc:Client|error {
    jdbc:Client dbClient = check new ("jdbc:sqlite:" + dbFile, connectionPool = {maxOpenConnections: 1});
    if resetDatabase {
        _ = check dbClient->execute(`DROP TABLE IF EXISTS assets`);
        _ = check dbClient->execute(`DROP TABLE IF EXISTS institutions`);
        _ = check dbClient->execute(`DROP TABLE IF EXISTS id_sequence`);
    }
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS institutions (
            institution_id TEXT PRIMARY KEY,
            name           TEXT NOT NULL UNIQUE,
            sites          TEXT NOT NULL DEFAULT '[]'
        )`);
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS assets (
            asset_tag     TEXT PRIMARY KEY,
            name          TEXT NOT NULL,
            description   TEXT NOT NULL DEFAULT '',
            institution   TEXT NOT NULL,
            site          TEXT NOT NULL,
            status        TEXT NOT NULL CHECK (status IN
                              ('AVAILABLE', 'LOANED_OUT', 'OCCUPIED', 'UNDER_MAINTENANCE', 'DISPOSED')),
            date_acquired TEXT NOT NULL,
            components    TEXT NOT NULL DEFAULT '[]',
            schedules     TEXT NOT NULL DEFAULT '[]',
            work_orders   TEXT NOT NULL DEFAULT '[]',
            current_loan  TEXT
        )`);
    _ = check dbClient->execute(`CREATE INDEX IF NOT EXISTS idx_assets_institution ON assets (institution, site)`);
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS id_sequence (
            name  TEXT PRIMARY KEY,
            value INTEGER NOT NULL
        )`);
    _ = check dbClient->execute(`INSERT OR IGNORE INTO id_sequence (name, value) VALUES ('id', 1000)`);
    return dbClient;
}

isolated function storeFailure(error cause) returns StoreError {
    return error StoreError("Database operation failed: " + cause.message(), cause);
}

# Runs an INSERT / UPDATE / DELETE and returns the number of affected rows.
isolated function runUpdate(sql:ParameterizedQuery statement) returns int|StoreError {
    sql:ExecutionResult|sql:Error result = db->execute(statement);
    if result is sql:Error {
        return storeFailure(result);
    }
    return result.affectedRowCount ?: 0;
}

# `true` when nothing has been stored yet, i.e. on the very first start.
public isolated function isDatabaseEmpty() returns boolean|StoreError {
    int count = check countRows(`SELECT COUNT(*) FROM institutions`);
    return count == 0;
}

# Generates a readable, monotonically increasing identifier such as `LN-1001`.
# The counter lives in the database so identifiers stay unique across restarts.
# The lock (shared with the writers in store.bal) stops two requests from
# reading the same counter value.
public isolated function nextId(string prefix) returns string|StoreError {
    lock {
        storeRevision += 1;
        int value = check incrementSequence();
        return prefix + "-" + value.toString();
    }
}

isolated function incrementSequence() returns int|StoreError {
    do {
        _ = check db->execute(`UPDATE id_sequence SET value = value + 1 WHERE name = 'id'`);
        int value = check db->queryRow(`SELECT value FROM id_sequence WHERE name = 'id'`);
        return value;
    } on fail error e {
        return storeFailure(e);
    }
}

isolated function countRows(sql:ParameterizedQuery query) returns int|StoreError {
    int|sql:Error count = db->queryRow(query);
    if count is sql:Error {
        return storeFailure(count);
    }
    return count;
}

// ------------------------------ institutions -------------------------------

type InstitutionRow record {|
    string institutionId;
    string name;
    string sites;
|};

isolated function queryInstitutions(sql:ParameterizedQuery whereClause) returns Institution[]|StoreError {
    do {
        stream<InstitutionRow, sql:Error?> rows = db->query(sql:queryConcat(
                `SELECT institution_id AS institutionId, name, sites FROM institutions `,
                whereClause, ` ORDER BY institution_id`));
        InstitutionRow[] collected = check from InstitutionRow row in rows select row;
        Institution[] institutions = [];
        foreach InstitutionRow row in collected {
            string[] sites = check row.sites.fromJsonStringWithType();
            institutions.push({institutionId: row.institutionId, name: row.name, sites: sites});
        }
        return institutions;
    } on fail error e {
        return storeFailure(e);
    }
}

isolated function loadInstitution(string institutionId) returns Institution|NotFoundError|StoreError {
    Institution[] found = check queryInstitutions(`WHERE institution_id = ${institutionId}`);
    if found.length() == 0 {
        return error NotFoundError("No institution registered with id '" + institutionId + "'");
    }
    return found[0];
}

isolated function institutionExists(string institutionId, string name) returns boolean|StoreError {
    int count = check countRows(
            `SELECT COUNT(*) FROM institutions WHERE institution_id = ${institutionId} OR name = ${name}`);
    return count > 0;
}

isolated function institutionIsRegistered(string name) returns boolean|StoreError {
    int count = check countRows(`SELECT COUNT(*) FROM institutions WHERE name = ${name}`);
    return count > 0;
}

isolated function countAssetsOwnedBy(string institutionName) returns int|StoreError {
    return countRows(`SELECT COUNT(*) FROM assets WHERE institution = ${institutionName}`);
}

isolated function deleteInstitutionRow(string institutionId) returns StoreError? {
    _ = check runUpdate(`DELETE FROM institutions WHERE institution_id = ${institutionId}`);
}

isolated function saveInstitution(Institution institution) returns StoreError? {
    _ = check runUpdate(`INSERT OR REPLACE INTO institutions (institution_id, name, sites)
            VALUES (${institution.institutionId}, ${institution.name}, ${institution.sites.toJsonString()})`);
}

// --------------------------------- assets ----------------------------------

type AssetRow record {|
    string assetTag;
    string name;
    string description;
    string institution;
    string site;
    string status;
    string dateAcquired;
    string components;
    string schedules;
    string workOrders;
    string? currentLoan;
|};

# Selects assets matching `whereClause` (e.g. `WHERE asset_tag = ${tag}`).
isolated function queryAssets(sql:ParameterizedQuery whereClause) returns Asset[]|StoreError {
    do {
        stream<AssetRow, sql:Error?> rows = db->query(sql:queryConcat(
                `SELECT asset_tag AS assetTag, name, description, institution, site, status,
                        date_acquired AS dateAcquired, components, schedules,
                        work_orders AS workOrders, current_loan AS currentLoan
                 FROM assets `, whereClause, ` ORDER BY asset_tag`));
        AssetRow[] collected = check from AssetRow row in rows select row;
        Asset[] assets = [];
        foreach AssetRow row in collected {
            assets.push(check toAsset(row));
        }
        return assets;
    } on fail error e {
        return storeFailure(e);
    }
}

isolated function toAsset(AssetRow row) returns Asset|error {
    AssetStatus status = check row.status.ensureType();
    Component[] components = check row.components.fromJsonStringWithType();
    Schedule[] schedules = check row.schedules.fromJsonStringWithType();
    WorkOrder[] workOrders = check row.workOrders.fromJsonStringWithType();
    Loan? currentLoan = ();
    string? loanJson = row.currentLoan;
    if loanJson is string {
        currentLoan = check loanJson.fromJsonStringWithType();
    }
    return {
        assetTag: row.assetTag,
        name: row.name,
        description: row.description,
        institution: row.institution,
        site: row.site,
        status: status,
        dateAcquired: row.dateAcquired,
        components: components,
        schedules: schedules,
        workOrders: workOrders,
        currentLoan: currentLoan
    };
}

# Reads one asset by its tag.
isolated function loadAsset(string assetTag) returns Asset|NotFoundError|StoreError {
    Asset[] found = check queryAssets(`WHERE asset_tag = ${assetTag}`);
    if found.length() == 0 {
        return error NotFoundError("No asset found with tag '" + assetTag + "'");
    }
    return found[0];
}

# Inserts the asset, or overwrites the stored row with the same tag.
isolated function saveAsset(Asset asset) returns StoreError? {
    Loan? loan = asset.currentLoan;
    string? loanJson = loan is Loan ? loan.toJsonString() : ();
    _ = check runUpdate(`INSERT OR REPLACE INTO assets
            (asset_tag, name, description, institution, site, status, date_acquired,
             components, schedules, work_orders, current_loan)
            VALUES (${asset.assetTag}, ${asset.name}, ${asset.description}, ${asset.institution},
                    ${asset.site}, ${asset.status}, ${asset.dateAcquired},
                    ${asset.components.toJsonString()}, ${asset.schedules.toJsonString()},
                    ${asset.workOrders.toJsonString()}, ${loanJson})`);
}

isolated function assetExists(string assetTag) returns boolean|StoreError {
    int count = check countRows(`SELECT COUNT(*) FROM assets WHERE asset_tag = ${assetTag}`);
    return count > 0;
}

# PATCH in one statement: a `()` argument is bound as SQL NULL, and
# `COALESCE(NULL, column)` keeps the stored value. Returns the number of rows
# changed (0 when the tag does not exist).
isolated function updateAssetFields(string assetTag, string? name, string? description, string? institution,
        string? site, AssetStatus? status, string? dateAcquired) returns int|StoreError {
    return runUpdate(`UPDATE assets SET
            name          = COALESCE(${name}, name),
            description   = COALESCE(${description}, description),
            institution   = COALESCE(${institution}, institution),
            site          = COALESCE(${site}, site),
            status        = COALESCE(${status}, status),
            date_acquired = COALESCE(${dateAcquired}, date_acquired)
        WHERE asset_tag = ${assetTag}`);
}

isolated function deleteAssetRow(string assetTag) returns StoreError? {
    _ = check runUpdate(`DELETE FROM assets WHERE asset_tag = ${assetTag}`);
}
