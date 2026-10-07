import ballerina/http;
import ballerina/io;
import ballerinax/java.jdbc;


// DATABASE CONNECTION


jdbc:Client dbClient = check new ("jdbc:sqlite:campuslibrary.db");


// DATABASE INITIALIZATION


function initDatabase() returns error? {

    // Assets table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS assets (
            assetTag TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            institution TEXT,
            site TEXT,
            status TEXT,
            dateAcquired TEXT
        )
    `);

    // Schedules table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS schedules (
            scheduleId TEXT PRIMARY KEY,
            assetTag TEXT NOT NULL,
            scheduleType TEXT NOT NULL,
            dueDate TEXT NOT NULL,
            description TEXT
        )
    `);

    // Components table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS components (
            compId TEXT PRIMARY KEY,
            assetTag TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT
        )
    `);

    // Work orders table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS work_orders (
            orderId TEXT PRIMARY KEY,
            assetTag TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL
        )
    `);

    // Work-order tasks table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS work_order_tasks (
            taskId TEXT PRIMARY KEY,
            orderId TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL
        )
    `);

    // Institutions table
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS institutions (
            institution TEXT PRIMARY KEY
        )
    `);

    // Add existing asset institutions to the institution list
    _ = check dbClient->execute(`
        INSERT OR IGNORE INTO institutions (institution)
        SELECT DISTINCT institution
        FROM assets
        WHERE institution IS NOT NULL
    `);
}


// DATA MODELS


public type Component record {|
    string compId;
    string name;
    string description;
|};

public type MaintenanceSchedule record {|
    string scheduleId;
    string scheduleType;
    string dueDate;
    string description;
|};

public type WorkOrder record {|
    string orderId;
    string description;
    string status;
|};

public type WorkOrderTask record {|
    string taskId;
    string description;
    string status;
|};

public type Asset record {|
    string assetTag;
    string name;
    string description;
    string institution;
    string site;
    string status;
    string dateAcquired;
    Component[] components?;
    MaintenanceSchedule[] schedules?;
    WorkOrder[] workOrders?;
|};

public type InstitutionRecord record {|
    string institution;
|};



// CORS CONFIGURATION


@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowCredentials: false,
        allowHeaders: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    }
}


// REST SERVICE


service / on new http:Listener(8080) {

    
    // SERVICE INITIALIZATION
    

    function init() returns error? {
        check initDatabase();
        io:println("Database initialized successfully!");
    }


    // WEB PAGE
   
    resource function get .() returns http:Response|error {
        http:Response res = new;
        res.setFileAsPayload(
            "index.html",
            contentType = "text/html"
        );
        return res;
    }


    // ASSET MANAGEMENT
    

    // GET: Retrieve all assets
    resource function get assets() returns Asset[]|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
            `);

        Asset[] assetsList =
            check from Asset a in assetStream
            select a;

        return assetsList;
    }


    // GET: Retrieve one asset by assetTag
    resource function get assets/[string assetTag]()
            returns Asset|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] assetsList =
            check from Asset a in assetStream
            select a;

        if assetsList.length() == 0 {
            return http:NOT_FOUND;
        }

        return assetsList[0];
    }


    // GET: Retrieve assets by institution
    resource function get assets/institution/[string institutionName]()
            returns Asset[]|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE institution = ${institutionName}
            `);

        Asset[] assetsList =
            check from Asset a in assetStream
            select a;

        return assetsList;
    }


    // GET: Retrieve assets by site
    resource function get assets/site/[string siteName]()
            returns Asset[]|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE site = ${siteName}
            `);

        Asset[] assetsList =
            check from Asset a in assetStream
            select a;

        return assetsList;
    }


    // GET: Retrieve assets whose maintenance date has passed
    resource function get assets/overdue()
            returns Asset[]|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT DISTINCT a.*
                FROM assets a
                INNER JOIN schedules s
                ON a.assetTag = s.assetTag
                WHERE s.dueDate < date('now')
                AND s.scheduleType = 'MAINTENANCE'
            `);

        Asset[] assetsList =
            check from Asset a in assetStream
            select a;

        return assetsList;
    }


    // GET: Retrieve all institutions
    resource function get assets/institutions()
            returns string[]|error {

        stream<InstitutionRecord, error?> instStream =
            dbClient->query(`
                SELECT institution
                FROM institutions
                ORDER BY institution
            `);

        string[] institutionsList =
            check from InstitutionRecord r in instStream
            select r.institution;

        return institutionsList;
    }


    // POST: Create a new asset
    resource function post assets(Asset newAsset)
            returns http:Created|error {

        _ = check dbClient->execute(`
            INSERT INTO assets
            (
                assetTag,
                name,
                description,
                institution,
                site,
                status,
                dateAcquired
            )
            VALUES
            (
                ${newAsset.assetTag},
                ${newAsset.name},
                ${newAsset.description},
                ${newAsset.institution},
                ${newAsset.site},
                ${newAsset.status},
                ${newAsset.dateAcquired}
            )
        `);

        // Also register the institution
        _ = check dbClient->execute(`
            INSERT OR IGNORE INTO institutions (institution)
            VALUES (${newAsset.institution})
        `);

        return http:CREATED;
    }


    // PUT: Update an existing asset
    resource function put assets/[string assetTag](
            Asset updatedAsset)
            returns http:Ok|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            UPDATE assets
            SET
                name = ${updatedAsset.name},
                description = ${updatedAsset.description},
                institution = ${updatedAsset.institution},
                site = ${updatedAsset.site},
                status = ${updatedAsset.status},
                dateAcquired = ${updatedAsset.dateAcquired}
            WHERE assetTag = ${assetTag}
        `);

        // Keep institution list updated
        _ = check dbClient->execute(`
            INSERT OR IGNORE INTO institutions (institution)
            VALUES (${updatedAsset.institution})
        `);

        return http:OK;
    }


    // DELETE: Remove an asset
    resource function delete assets/[string assetTag]()
            returns http:Ok|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            DELETE FROM assets
            WHERE assetTag = ${assetTag}
        `);

        return http:OK;
    }


    // POST: Loan an asset
    resource function post assets/[string assetTag]/loan()
            returns http:Ok|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            UPDATE assets
            SET status = 'NOT AVAILABLE'
            WHERE assetTag = ${assetTag}
        `);

        return http:OK;
    }


    
    // SCHEDULE MANAGEMENT
    

    // GET: Retrieve schedules for an asset
    resource function get assets/[string assetTag]/schedules()
            returns MaintenanceSchedule[]|error {

        stream<MaintenanceSchedule, error?> scheduleStream =
            dbClient->query(`
                SELECT
                    scheduleId,
                    scheduleType,
                    dueDate,
                    description
                FROM schedules
                WHERE assetTag = ${assetTag}
            `);

        MaintenanceSchedule[] schedules =
            check from MaintenanceSchedule s in scheduleStream
            select s;

        return schedules;
    }


    // POST: Add a schedule
    resource function post assets/[string assetTag]/schedules(
            MaintenanceSchedule schedule)
            returns http:Created|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            INSERT INTO schedules
            (
                scheduleId,
                assetTag,
                scheduleType,
                dueDate,
                description
            )
            VALUES
            (
                ${schedule.scheduleId},
                ${assetTag},
                ${schedule.scheduleType},
                ${schedule.dueDate},
                ${schedule.description}
            )
        `);

        return http:CREATED;
    }


    // DELETE: Remove a schedule
    resource function delete assets/[string assetTag]/schedules/[string scheduleId]()
            returns http:Ok|http:NotFound|error {

        _ = check dbClient->execute(`
            DELETE FROM schedules
            WHERE assetTag = ${assetTag}
            AND scheduleId = ${scheduleId}
        `);

        return http:OK;
    }


    // COMPONENT MANAGEMENT
    

    // GET: Retrieve components of an asset
    resource function get assets/[string assetTag]/components()
            returns Component[]|error {

        stream<Component, error?> componentStream =
            dbClient->query(`
                SELECT
                    compId,
                    name,
                    description
                FROM components
                WHERE assetTag = ${assetTag}
            `);

        Component[] components =
            check from Component c in componentStream
            select c;

        return components;
    }


    // POST: Add a component
    resource function post assets/[string assetTag]/components(
            Component component)
            returns http:Created|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            INSERT INTO components
            (
                compId,
                assetTag,
                name,
                description
            )
            VALUES
            (
                ${component.compId},
                ${assetTag},
                ${component.name},
                ${component.description}
            )
        `);

        return http:CREATED;
    }


    // DELETE: Remove a component
    resource function delete assets/[string assetTag]/components/[string compId]()
            returns http:Ok|http:NotFound|error {

        _ = check dbClient->execute(`
            DELETE FROM components
            WHERE assetTag = ${assetTag}
            AND compId = ${compId}
        `);

        return http:OK;
    }


    // WORK ORDER MANAGEMENT
    

    // GET: Retrieve work orders
    resource function get assets/[string assetTag]/workorders()
            returns WorkOrder[]|error {

        stream<WorkOrder, error?> workOrderStream =
            dbClient->query(`
                SELECT
                    orderId,
                    description,
                    status
                FROM work_orders
                WHERE assetTag = ${assetTag}
            `);

        WorkOrder[] workOrders =
            check from WorkOrder w in workOrderStream
            select w;

        return workOrders;
    }


    // POST: Open a work order
    resource function post assets/[string assetTag]/workorders(
            WorkOrder workOrder)
            returns http:Created|http:NotFound|error {

        stream<Asset, error?> assetStream =
            dbClient->query(`
                SELECT * FROM assets
                WHERE assetTag = ${assetTag}
            `);

        Asset[] existingAssets =
            check from Asset a in assetStream
            select a;

        if existingAssets.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            INSERT INTO work_orders
            (
                orderId,
                assetTag,
                description,
                status
            )
            VALUES
            (
                ${workOrder.orderId},
                ${assetTag},
                ${workOrder.description},
                ${workOrder.status}
            )
        `);

        return http:CREATED;
    }


    // PUT: Update or close a work order
    resource function put assets/[string assetTag]/workorders/[string orderId](
            WorkOrder workOrder)
            returns http:Ok|http:NotFound|error {

        stream<WorkOrder, error?> workOrderStream =
            dbClient->query(`
                SELECT
                    orderId,
                    description,
                    status
                FROM work_orders
                WHERE orderId = ${orderId}
                AND assetTag = ${assetTag}
            `);

        WorkOrder[] existingOrders =
            check from WorkOrder w in workOrderStream
            select w;

        if existingOrders.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            UPDATE work_orders
            SET
                description = ${workOrder.description},
                status = ${workOrder.status}
            WHERE orderId = ${orderId}
            AND assetTag = ${assetTag}
        `);

        return http:OK;
    }


    // POST: Add a task to a work order
    resource function post assets/[string assetTag]/workorders/[string orderId]/tasks(
            WorkOrderTask task)
            returns http:Created|http:NotFound|error {

        stream<WorkOrder, error?> workOrderStream =
            dbClient->query(`
                SELECT
                    orderId,
                    description,
                    status
                FROM work_orders
                WHERE orderId = ${orderId}
                AND assetTag = ${assetTag}
            `);

        WorkOrder[] existingOrders =
            check from WorkOrder w in workOrderStream
            select w;

        if existingOrders.length() == 0 {
            return http:NOT_FOUND;
        }

        _ = check dbClient->execute(`
            INSERT INTO work_order_tasks
            (
                taskId,
                orderId,
                description,
                status
            )
            VALUES
            (
                ${task.taskId},
                ${orderId},
                ${task.description},
                ${task.status}
            )
        `);

        return http:CREATED;
    }


    // GET: Retrieve work-order tasks
    resource function get assets/[string assetTag]/workorders/[string orderId]/tasks()
            returns WorkOrderTask[]|error {

        stream<WorkOrderTask, error?> taskStream =
            dbClient->query(`
                SELECT
                    taskId,
                    description,
                    status
                FROM work_order_tasks
                WHERE orderId = ${orderId}
            `);

        WorkOrderTask[] tasks =
            check from WorkOrderTask t in taskStream
            select t;

        return tasks;
    }


    // INSTITUTION MANAGEMENT
    

    // POST: Add an institution
    resource function post institutions(string institution)
            returns http:Created|error {

        _ = check dbClient->execute(`
            INSERT INTO institutions (institution)
            VALUES (${institution})
        `);

        return http:CREATED;
    }


    // DELETE: Remove an institution
    resource function delete institutions/[string institution]()
            returns http:Ok|http:NotFound|error {

        _ = check dbClient->execute(`
            DELETE FROM institutions
            WHERE institution = ${institution}
        `);

        return http:OK;
    }
}