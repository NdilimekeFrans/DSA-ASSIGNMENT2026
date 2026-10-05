import ballerina/http;
import ballerina/io;
import ballerinax/java.jdbc;
jdbc:Client dbClient = check new ("jdbc:sqlite:campuslibrary.db");
function initDatabase() returns error? {
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
}
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

public type Task record {|
    string taskId;
    string description;
|};

public type WorkOrder record {|
    string orderId;
    string status;
    string description;
    Task[] tasks;
|};

public type Asset record {|
    readonly string assetTag;
    string name;
    string description;
    string institution;
    string site;
    string status;
    string dateAcquired;
    Component[] components;
    MaintenanceSchedule[] schedules;
    WorkOrder[] workOrders;
|};

table<Asset> key(assetTag) assets = table [
    {
        assetTag: "NUST-LIB-3DP-001",
        name: "Pro-Series 3D Printer",
        description: "High-precision laboratory printer",
        institution: "Namibia University of Science and Technology",
        site: "Main Campus - Innovation Lab",
        status: "AVAILABLE",
        dateAcquired: "2024-03-10",

        components: [
            {
                compId: "C101",
                name: "High-Torque Stepper Motor",
                description: "Main motor for X-axis movement."
            }
        ],

        schedules: [
            {
                scheduleId: "SCH-882",
                scheduleType: "MAINTENANCE",
                dueDate: "2026-09-01",
                description: "Quarterly calibration and nozzle cleaning."
            }
        ],

        workOrders: [
            {
                orderId: "WO-554",
                status: "OPEN",
                description: "Nozzle heat-bed failure",
                tasks: [
                    {
                        taskId: "T1",
                        description: "Check thermal sensor connectivity."
                    }
                ]
            }
        ]
    }
];

service /assets on new http:Listener(8080) {

    // GET ALL ASSETS
    resource function get .() returns Asset[] {
        return assets.toArray();
    }

    // GET ONE ASSET
    resource function get [string assetTag]() returns Asset|http:NotFound {
        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        return asset;
    }

    // GET ASSETS BY INSTITUTION
    resource function get institution/[string institution]() returns Asset[] {
        return from Asset asset in assets
            where asset.institution == institution
            select asset;
    }

    // GET ASSETS BY SITE
    resource function get site/[string site]() returns Asset[] {
        return from Asset asset in assets
            where asset.site == site
            select asset;
    }

 // GET ALL INSTITUTIONS
resource function get institutions() returns string[] {
    string[] institutions = [];

    foreach Asset asset in assets {
        boolean exists = false;

        foreach string institution in institutions {
            if institution == asset.institution {
                exists = true;
                break;
            }
        }

        if !exists {
            institutions.push(asset.institution);
        }
    }

    return institutions;
}
    // CHECK ASSET STATUS
    resource function get [string assetTag]/status()
            returns string|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        return asset.status;
    }

    // VIEW ASSET SCHEDULES
    resource function get [string assetTag]/schedules()
            returns MaintenanceSchedule[]|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        return asset.schedules;
    }

    // CHECK OVERDUE MAINTENANCE
    resource function get overdue() returns Asset[] {
        Asset[] overdueAssets = [];

        foreach Asset asset in assets {
            foreach MaintenanceSchedule schedule in asset.schedules {
                if schedule.dueDate < "2026-09-04" {
                    overdueAssets.push(asset);
                    break;
                }
            }
        }

        return overdueAssets;
    }

    // ADD COMPONENT
    resource function post [string assetTag]/components(Component newComponent)
            returns Component|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        asset.components.push(newComponent);
        assets.put(asset);

        return newComponent;
    }

    // REMOVE COMPONENT
    resource function delete [string assetTag]/components/[string compId]()
            returns http:NoContent|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        Component[] updatedComponents = [];

        foreach Component component in asset.components {
            if component.compId != compId {
                updatedComponents.push(component);
            }
        }

        asset.components = updatedComponents;
        assets.put(asset);

        return http:NO_CONTENT;
    }

    // ADD SCHEDULE
    resource function post [string assetTag]/schedules(
            MaintenanceSchedule newSchedule)
            returns MaintenanceSchedule|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        asset.schedules.push(newSchedule);
        assets.put(asset);

        return newSchedule;
    }


 // UPDATE SCHEDULE
resource function put [string assetTag]/schedules/[string scheduleId](
        MaintenanceSchedule updatedSchedule)
        returns MaintenanceSchedule|http:NotFound {

    Asset? asset = assets[assetTag];

    if asset is () {
        return http:NOT_FOUND;
    }

    foreach int i in 0 ..< asset.schedules.length() {
        if asset.schedules[i].scheduleId == scheduleId {
            asset.schedules[i] = updatedSchedule;
            assets.put(asset);
            return updatedSchedule;
        }
    }
        return http:NOT_FOUND;
}


    // REMOVE SCHEDULE
    resource function delete [string assetTag]/schedules/[string scheduleId]()
            returns http:NoContent|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        MaintenanceSchedule[] updatedSchedules = [];

        foreach MaintenanceSchedule schedule in asset.schedules {
            if schedule.scheduleId != scheduleId {
                updatedSchedules.push(schedule);
            }
        }

        asset.schedules = updatedSchedules;
        assets.put(asset);

        return http:NO_CONTENT;
    }

    // VIEW WORK ORDERS
    resource function get [string assetTag]/workorders()
            returns WorkOrder[]|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        return asset.workOrders;
    }

    // ADD WORK ORDER
    resource function post [string assetTag]/workorders(
            WorkOrder newWorkOrder)
            returns WorkOrder|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        asset.workOrders.push(newWorkOrder);
        assets.put(asset);

        return newWorkOrder;
    }

    // UPDATE WORK ORDER
    resource function put [string assetTag]/workorders/[string orderId](
            WorkOrder updatedWorkOrder)
            returns WorkOrder|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        foreach int i in 0 ..< asset.workOrders.length() {
            if asset.workOrders[i].orderId == orderId {
                asset.workOrders[i] = updatedWorkOrder;
                assets.put(asset);
                return updatedWorkOrder;
            }
        }

        return http:NOT_FOUND;
    }

    // DELETE WORK ORDER
    resource function delete [string assetTag]/workorders/[string orderId]()
            returns http:NoContent|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        WorkOrder[] updatedWorkOrders = [];

        foreach WorkOrder workOrder in asset.workOrders {
            if workOrder.orderId != orderId {
                updatedWorkOrders.push(workOrder);
            }
        }

        asset.workOrders = updatedWorkOrders;
        assets.put(asset);

        return http:NO_CONTENT;
    }

    // ADD TASK TO WORK ORDER
    resource function post [string assetTag]/workorders/[string orderId]/tasks(
            Task newTask)
            returns Task|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        foreach WorkOrder workOrder in asset.workOrders {
            if workOrder.orderId == orderId {
                workOrder.tasks.push(newTask);
                assets.put(asset);
                return newTask;
            }
        }

        return http:NOT_FOUND;
    }

    // VIEW TASKS
    resource function get [string assetTag]/workorders/[string orderId]/tasks()
            returns Task[]|http:NotFound {

        Asset? asset = assets[assetTag];

        if asset is () {
            return http:NOT_FOUND;
        }

        foreach WorkOrder workOrder in asset.workOrders {
            if workOrder.orderId == orderId {
                return workOrder.tasks;
            }
        }

        return http:NOT_FOUND;
    }

    // LOAN ASSET
resource function post [string assetTag]/loan()
        returns Asset|http:NotFound {

    Asset? asset = assets[assetTag];

    if asset is () {
        return http:NOT_FOUND;
    }

    asset.status = "LOANED_OUT";
    assets.put(asset);

    return asset;
}

// BOOK RESOURCE
resource function post [string assetTag]/book()
        returns Asset|http:NotFound {

    Asset? asset = assets[assetTag];

    if asset is () {
        return http:NOT_FOUND;
    }

    asset.status = "OCCUPIED";
    assets.put(asset);

    return asset;
}

    // CREATE ASSET
   resource function post .(Asset newAsset) returns Asset|error {
    assets.add(newAsset);

  _ = check dbClient->execute(`
    INSERT INTO assets
    (assetTag, name, description, institution, site, status, dateAcquired)
    VALUES (
        ${newAsset.assetTag},
        ${newAsset.name},
        ${newAsset.description},
        ${newAsset.institution},
        ${newAsset.site},
        ${newAsset.status},
        ${newAsset.dateAcquired}
    )
`);

    return newAsset;
}

    // UPDATE ASSET
    resource function put [string assetTag](Asset updatedAsset)
            returns Asset|http:NotFound {

        Asset? existingAsset = assets[assetTag];

        if existingAsset is () {
            return http:NOT_FOUND;
        }

        assets.put(updatedAsset);
        return updatedAsset;
    }

    // DELETE ASSET
    resource function delete [string assetTag]()
            returns http:NoContent|http:NotFound {

        Asset? existingAsset = assets[assetTag];

        if existingAsset is () {
            return http:NOT_FOUND;
        }

        _ = assets.remove(assetTag);

        return http:NO_CONTENT;
    }
}

public function main() returns error? {

    check initDatabase();

    io:println("Campus Library REST API running on port 8080");

}