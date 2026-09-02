import ballerina/http;
import ballerina/io;

// ---------------------------------------------------------------------------
// Command-line console for the Distributed Library and Resource Management
// System. It talks to the Ballerina REST backend over HTTP and exercises every
// operation the API exposes: the global view, the campus view, the overdue
// dashboard, loans and room bookings, schedules, components and work orders.
// ---------------------------------------------------------------------------

configurable string apiUrl = "http://localhost:8080/library";

final http:Client libraryApi = check new (apiUrl);

public function main() returns error? {
    io:println();
    io:println("=========================================================");
    io:println(" Ministry of Higher Education, Training and Innovations");
    io:println(" Distributed Library and Resource Management System");
    io:println(" Connected to: ", apiUrl);
    io:println("=========================================================");

    check checkConnection();

    while true {
        printMenu();
        string choice = io:readln("Select an option: ").trim();
        io:println();
        if choice == "0" {
            io:println("Goodbye.");
            return;
        }
        error? outcome = dispatch(choice);
        if outcome is error {
            report(outcome);
        }
        io:println();
    }
}

function dispatch(string choice) returns error? {
    match choice {
        "1" => {
            return viewAllAssets();
        }
        "2" => {
            return viewByCampus();
        }
        "3" => {
            return lookupAsset();
        }
        "4" => {
            return createAsset();
        }
        "5" => {
            return updateAsset();
        }
        "6" => {
            return deleteAsset();
        }
        "7" => {
            return loanAsset();
        }
        "8" => {
            return returnAsset();
        }
        "9" => {
            return bookSpace();
        }
        "10" => {
            return overdueDashboard();
        }
        "11" => {
            return manageSchedules();
        }
        "12" => {
            return manageComponents();
        }
        "13" => {
            return manageWorkOrders();
        }
        "14" => {
            return manageInstitutions();
        }
    }
    io:println("Unknown option '", choice, "'. Please choose a number from the menu.");
    return;
}

function printMenu() {
    io:println("---------------------------------------------------------");
    io:println(" 1. Global view - all assets in the Ministry");
    io:println(" 2. Campus view - filter by institution / site / status");
    io:println(" 3. Look up an asset by tag");
    io:println(" 4. Register a new asset");
    io:println(" 5. Update an asset");
    io:println(" 6. Remove an asset");
    io:println(" 7. Loan an asset out");
    io:println(" 8. Return a loaned asset");
    io:println(" 9. Book a lab or meeting room");
    io:println("10. Overdue dashboard");
    io:println("11. Schedule manager (add / remove)");
    io:println("12. Component manager (add / remove)");
    io:println("13. Work orders and tasks");
    io:println("14. Institutions (list / add / remove)");
    io:println(" 0. Exit");
    io:println("---------------------------------------------------------");
}

// ------------------------------- operations --------------------------------

function checkConnection() returns error? {
    record {|string status; int assets;|}|error health = libraryApi->get("/health");
    if health is error {
        io:println();
        io:println("Cannot reach the API at ", apiUrl);
        io:println("Start the backend first:  cd question1-library-api && bal run");
        return health;
    }
    io:println(" Service status: ", health.status, " (", health.assets, " assets registered)");
    io:println();
    return;
}

function viewAllAssets() returns error? {
    Asset[] assets = check libraryApi->get("/assets");
    printAssetTable(assets, "All assets across the Ministry");
    return;
}

function viewByCampus() returns error? {
    string institution = io:readln("Institution (blank for all): ").trim();
    string site = io:readln("Site / campus (blank for all): ").trim();
    string status = io:readln("Status (blank for any): ").trim().toUpperAscii();

    string[] query = [];
    if institution != "" {
        query.push("institution=" + encode(institution));
    }
    if site != "" {
        query.push("site=" + encode(site));
    }
    if status != "" {
        query.push("status=" + encode(status));
    }
    string path = "/assets" + (query.length() > 0 ? "?" + string:'join("&", ...query) : "");

    Asset[] assets = check libraryApi->get(path);
    printAssetTable(assets, "Filtered view");
    return;
}

function lookupAsset() returns error? {
    string tag = io:readln("Asset tag: ").trim();
    Asset asset = check libraryApi->get("/assets/" + encode(tag));
    printAssetDetail(asset);
    return;
}

function createAsset() returns error? {
    Asset asset = {
        assetTag: io:readln("Asset tag        : ").trim(),
        name: io:readln("Name             : ").trim(),
        description: io:readln("Description      : ").trim(),
        institution: io:readln("Institution      : ").trim(),
        site: io:readln("Site / campus    : ").trim(),
        dateAcquired: io:readln("Date acquired    : ").trim(),
        status: AVAILABLE
    };
    Asset created = check libraryApi->post("/assets", asset);
    io:println("Registered ", created.assetTag, ".");
    return;
}

function updateAsset() returns error? {
    string tag = io:readln("Asset tag to update: ").trim();
    io:println("Leave a field blank to keep its current value.");
    map<string> changes = {};
    addIfPresent(changes, "name", io:readln("New name        : "));
    addIfPresent(changes, "description", io:readln("New description : "));
    addIfPresent(changes, "site", io:readln("New site        : "));
    addIfPresent(changes, "status", io:readln("New status      : "));
    if changes.length() == 0 {
        io:println("Nothing to change.");
        return;
    }
    Asset updated = check libraryApi->patch("/assets/" + encode(tag), changes);
    printAssetDetail(updated);
    return;
}

function addIfPresent(map<string> changes, string field, string value) {
    string trimmed = value.trim();
    if trimmed != "" {
        changes[field] = field == "status" ? trimmed.toUpperAscii() : trimmed;
    }
}

function deleteAsset() returns error? {
    string tag = io:readln("Asset tag to remove: ").trim();
    string confirmation = io:readln("Type the tag again to confirm: ").trim();
    if confirmation != tag {
        io:println("Cancelled.");
        return;
    }
    Asset removed = check libraryApi->delete("/assets/" + encode(tag));
    io:println("Removed ", removed.assetTag, " (", removed.name, ").");
    return;
}

function loanAsset() returns error? {
    string tag = io:readln("Asset tag  : ").trim();
    json request = {
        borrower: io:readln("Borrower   : ").trim(),
        dueDate: io:readln("Due back   : ").trim()
    };
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/loan", request);
    Loan? loan = asset.currentLoan;
    if loan is Loan {
        io:println("Loan ", loan.loanId, " created for ", loan.borrower, ", due ", loan.dueDate, ".");
    }
    return;
}

function returnAsset() returns error? {
    string tag = io:readln("Asset tag: ").trim();
    json emptyBody = {};
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/return", emptyBody);
    io:println(asset.assetTag, " is back on the shelf and ", asset.status, ".");
    return;
}

function bookSpace() returns error? {
    string tag = io:readln("Asset tag (lab / room) : ").trim();
    json request = {
        bookedBy: io:readln("Booked by              : ").trim(),
        startDate: io:readln("From (YYYY-MM-DD)      : ").trim(),
        endDate: io:readln("To   (YYYY-MM-DD)      : ").trim(),
        description: io:readln("Purpose                : ").trim()
    };
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/bookings", request);
    io:println("Booked. ", asset.assetTag, " is now ", asset.status, ".");
    printSchedules(asset);
    return;
}

function overdueDashboard() returns error? {
    OverdueEntry[] schedules = check libraryApi->get("/maintenance/overdue");
    io:println("== Elapsed maintenance and servicing schedules ==");
    if schedules.length() == 0 {
        io:println("  Nothing is overdue.");
    } else {
        io:println("  ", fit("ASSET TAG", 22), fit("TYPE", 14), fit("DUE", 12), fit("LATE", 7), "ASSET");
        foreach OverdueEntry entry in schedules {
            io:println("  ", fit(entry.assetTag, 22), fit(entry.scheduleType, 14),
                    fit(entry.dueDate, 12), fit(entry.daysOverdue.toString() + "d", 7), entry.name);
        }
    }

    OverdueLoan[] loans = check libraryApi->get("/loans/overdue");
    io:println();
    io:println("== Overdue loans ==");
    if loans.length() == 0 {
        io:println("  No loans are overdue.");
        return;
    }
    io:println("  ", fit("ASSET TAG", 22), fit("BORROWER", 20), fit("DUE", 12), "LATE");
    foreach OverdueLoan loan in loans {
        io:println("  ", fit(loan.assetTag, 22), fit(loan.borrower, 20), fit(loan.dueDate, 12),
                loan.daysOverdue, "d");
    }
    return;
}

function manageSchedules() returns error? {
    string action = io:readln("(a)dd or (r)emove a schedule? ").trim().toLowerAscii();
    string tag = io:readln("Asset tag   : ").trim();
    if action == "r" {
        string scheduleId = io:readln("Schedule id : ").trim();
        Asset asset = check libraryApi->delete("/assets/" + encode(tag) + "/schedules/"
                + encode(scheduleId));
        io:println("Schedule removed.");
        printSchedules(asset);
        return;
    }
    json schedule = {
        scheduleId: io:readln("Schedule id : ").trim(),
        'type: io:readln("Type (MAINTENANCE/SERVICING/INSPECTION): ").trim().toUpperAscii(),
        dueDate: io:readln("Due date    : ").trim(),
        description: io:readln("Description : ").trim()
    };
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/schedules", schedule);
    io:println("Schedule added.");
    printSchedules(asset);
    return;
}

function manageComponents() returns error? {
    string action = io:readln("(a)dd or (r)emove a component? ").trim().toLowerAscii();
    string tag = io:readln("Asset tag    : ").trim();
    if action == "r" {
        string compId = io:readln("Component id : ").trim();
        Asset asset = check libraryApi->delete("/assets/" + encode(tag) + "/components/" + encode(compId));
        io:println("Component removed. ", asset.components.length(), " remaining.");
        return;
    }
    json component = {
        compId: io:readln("Component id : ").trim(),
        name: io:readln("Name         : ").trim(),
        description: io:readln("Description  : ").trim()
    };
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/components", component);
    io:println("Component added. The asset now has ", asset.components.length(), " components.");
    return;
}

function manageWorkOrders() returns error? {
    io:println("(o)pen a work order, (u)pdate its status, (t)ask add, (l)ist");
    string action = io:readln("Choice     : ").trim().toLowerAscii();
    string tag = io:readln("Asset tag  : ").trim();

    if action == "l" {
        WorkOrder[] orders = check libraryApi->get("/assets/" + encode(tag) + "/workorders");
        if orders.length() == 0 {
            io:println("No work orders on this asset.");
            return;
        }
        foreach WorkOrder order in orders {
            io:println("  ", fit(order.orderId, 12), fit(order.status, 14), order.description);
            foreach Task task in order.tasks {
                io:println("      - ", fit(task.taskId, 10), task.description);
            }
        }
        return;
    }
    if action == "u" {
        string orderId = io:readln("Order id   : ").trim();
        json update = {status: io:readln("New status (OPEN/IN_PROGRESS/CLOSED): ").trim().toUpperAscii()};
        Asset asset = check libraryApi->put("/assets/" + encode(tag) + "/workorders/"
                + encode(orderId), update);
        io:println("Work order updated. Asset is now ", asset.status, ".");
        return;
    }
    if action == "t" {
        string orderId = io:readln("Order id   : ").trim();
        json task = {taskId: "", description: io:readln("Task       : ").trim()};
        Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/workorders/"
                + encode(orderId) + "/tasks", task);
        io:println("Task added to ", orderId, ". The asset now has ",
                asset.workOrders.length(), " work order(s).");
        return;
    }
    json workOrder = {orderId: "", status: "OPEN", description: io:readln("Fault      : ").trim()};
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/workorders", workOrder);
    WorkOrder opened = asset.workOrders[asset.workOrders.length() - 1];
    io:println("Opened work order ", opened.orderId, ". Asset is now ", asset.status, ".");
    return;
}

function manageInstitutions() returns error? {
    io:println("(l)ist, (a)dd or (r)emove an institution");
    string action = io:readln("Choice : ").trim().toLowerAscii();

    if action == "a" {
        json institution = {
            institutionId: io:readln("Id     : ").trim(),
            name: io:readln("Name   : ").trim(),
            sites: [io:readln("Site   : ").trim()]
        };
        Institution added = check libraryApi->post("/institutions", institution);
        io:println("Registered ", added.name, ".");
        return;
    }
    if action == "r" {
        string institutionId = io:readln("Id : ").trim();
        Institution removed = check libraryApi->delete("/institutions/" + encode(institutionId));
        io:println("Removed ", removed.name, " from the listing.");
        return;
    }
    Institution[] institutions = check libraryApi->get("/institutions");
    io:println("  ", fit("ID", 10), fit("NAME", 52), "SITES");
    foreach Institution institution in institutions {
        io:println("  ", fit(institution.institutionId, 10), fit(institution.name, 52),
                string:'join(", ", ...institution.sites));
    }
    return;
}

// -------------------------------- rendering --------------------------------

function printAssetTable(Asset[] assets, string title) {
    io:println("== ", title, " (", assets.length(), ") ==");
    if assets.length() == 0 {
        io:println("  Nothing to show.");
        return;
    }
    io:println("  ", fit("ASSET TAG", 22), fit("NAME", 34), fit("SITE", 30), fit("STATUS", 18), "ACQUIRED");
    foreach Asset asset in assets {
        io:println("  ", fit(asset.assetTag, 22), fit(asset.name, 34), fit(asset.site, 30),
                fit(asset.status, 18), asset.dateAcquired);
    }
}

function printAssetDetail(Asset asset) {
    io:println("Asset tag    : ", asset.assetTag);
    io:println("Name         : ", asset.name);
    io:println("Description  : ", asset.description);
    io:println("Institution  : ", asset.institution);
    io:println("Site         : ", asset.site);
    io:println("Status       : ", asset.status);
    io:println("Acquired     : ", asset.dateAcquired);

    Loan? loan = asset.currentLoan;
    if loan is Loan {
        io:println("On loan to   : ", loan.borrower, " until ", loan.dueDate, " (", loan.loanId, ")");
    }
    if asset.components.length() > 0 {
        io:println("Components   :");
        foreach Component component in asset.components {
            io:println("   - ", fit(component.compId, 10), component.name);
        }
    }
    printSchedules(asset);
    if asset.workOrders.length() > 0 {
        io:println("Work orders  :");
        foreach WorkOrder order in asset.workOrders {
            io:println("   - ", fit(order.orderId, 12), fit(order.status, 14), order.description);
            foreach Task task in order.tasks {
                io:println("        * ", task.description);
            }
        }
    }
}

function printSchedules(Asset asset) {
    if asset.schedules.length() == 0 {
        return;
    }
    io:println("Schedules    :");
    foreach Schedule schedule in asset.schedules {
        string period = schedule.endDate is string ? schedule.dueDate + " -> " + (schedule.endDate ?: "")
            : schedule.dueDate;
        io:println("   - ", fit(schedule.scheduleId, 12), fit(schedule.'type, 14), fit(period, 26),
                schedule.description);
    }
}

// --------------------------------- helpers ---------------------------------

# Pads or truncates a value so the console output lines up in columns.
function fit(string value, int width) returns string {
    string text = value;
    if text.length() >= width {
        return text.substring(0, width - 1) + " ";
    }
    int padding = width - text.length();
    int index = 0;
    while index < padding {
        text += " ";
        index += 1;
    }
    return text;
}

# Minimal percent-encoding for the characters that occur in institution names
# and asset tags.
function encode(string value) returns string {
    string encoded = "";
    foreach string:Char character in value {
        match character {
            " " => {
                encoded += "%20";
            }
            "&" => {
                encoded += "%26";
            }
            "?" => {
                encoded += "%3F";
            }
            "#" => {
                encoded += "%23";
            }
            "/" => {
                encoded += "%2F";
            }
            _ => {
                encoded += character;
            }
        }
    }
    return encoded;
}

# Prints a server-side failure in a way a user can act on: the HTTP status and
# the uniform error body the API returns.
function report(error e) {
    if e is http:ClientRequestError {
        http:Detail detail = e.detail();
        io:println("  ! HTTP ", detail.statusCode, " - ", detail.body.toJsonString());
        return;
    }
    if e is http:RemoteServerError {
        http:Detail detail = e.detail();
        io:println("  ! HTTP ", detail.statusCode, " - ", detail.body.toJsonString());
        return;
    }
    io:println("  ! ", e.message());
}
