import ballerina/http;
import ballerina/io;
import ballerina/time;

// ---------------------------------------------------------------------------
// Command-line console for the Distributed Library and Resource Management
// System. It talks to the Ballerina REST backend over HTTP and exercises every
// operation the API exposes: the global view, the campus view, the overdue
// dashboard, loans and room bookings, schedules, components, work orders and
// institutions.
//
// Every choice is made from a numbered menu, inputs are checked before they
// are sent, and server errors are shown as a short readable message.
// ---------------------------------------------------------------------------

configurable string apiUrl = "http://localhost:8080/library";

final http:Client libraryApi = check new (apiUrl);

final string[] & readonly ASSET_STATUSES = ["AVAILABLE", "LOANED_OUT", "OCCUPIED", "UNDER_MAINTENANCE", "DISPOSED"];
final string[] & readonly SCHEDULE_TYPES = ["MAINTENANCE", "SERVICING", "INSPECTION"];
final string[] & readonly WORK_ORDER_STATUSES = ["OPEN", "IN_PROGRESS", "CLOSED"];

public function main() {
    io:println();
    io:println("=========================================================");
    io:println(" Ministry of Higher Education, Training and Innovations");
    io:println(" Distributed Library and Resource Management System");
    io:println(" Connected to: ", apiUrl);
    io:println("=========================================================");

    while !isConnected() {
        io:println();
        io:println("Cannot reach the API at ", apiUrl);
        io:println("Start the backend first:  cd question1-library-api && bal run");
        string again = io:readln("Press Enter to try again, or type 0 to exit: ").trim();
        if again == "0" {
            io:println("Goodbye.");
            return;
        }
    }

    while true {
        printMenu();
        string choice = io:readln("Select an option: ").trim();
        io:println();
        if choice == "0" {
            io:println("Goodbye.");
            return;
        }
        if choice == "" {
            continue;
        }
        error? outcome = dispatch(choice);
        if outcome is error {
            report(outcome);
        }
        pause();
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
    io:println();
    io:println("========================= MAIN MENU =====================");
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
    io:println("11. Schedules   (list / add / remove)");
    io:println("12. Components  (list / add / remove)");
    io:println("13. Work orders and tasks");
    io:println("14. Institutions and sites");
    io:println(" 0. Exit");
    io:println("=========================================================");
}

// ------------------------------- operations --------------------------------

function isConnected() returns boolean {
    record {|string status; int assets;|}|error health = libraryApi->get("/health");
    if health is error {
        return false;
    }
    io:println(" Service status: ", health.status, " (", health.assets, " assets registered)");
    return true;
}

function viewAllAssets() returns error? {
    Asset[] assets = check libraryApi->get("/assets");
    printAssetTable(assets, "All assets across the Ministry");
    return;
}

function viewByCampus() returns error? {
    string[] query = [];

    Institution? institution = check pickInstitution("Filter by institution", true);
    if institution is Institution {
        query.push("institution=" + encode(institution.name));
        string? site = pickFrom("Filter by site / campus", institution.sites, true);
        if site is string {
            query.push("site=" + encode(site));
        }
    }
    string? status = pickFrom("Filter by status", ASSET_STATUSES, true);
    if status is string {
        query.push("status=" + status);
    }

    string path = "/assets" + (query.length() > 0 ? "?" + string:'join("&", ...query) : "");
    Asset[] assets = check libraryApi->get(path);
    printAssetTable(assets, "Filtered view");
    return;
}

function lookupAsset() returns error? {
    string tag = readRequired("Asset tag: ");
    Asset asset = check libraryApi->get("/assets/" + encode(tag));
    printAssetDetail(asset);
    return;
}

function createAsset() returns error? {
    string tag = readRequired("Asset tag        : ");
    string name = readRequired("Name             : ");
    string description = io:readln("Description      : ").trim();

    Institution? institution = check pickInstitution("Owning institution", false);
    if institution is () {
        return;
    }
    string site = pickSite(institution);
    string dateAcquired = readDate("Date acquired (YYYY-MM-DD, blank for today): ", today());

    Asset asset = {
        assetTag: tag,
        name: name,
        description: description,
        institution: institution.name,
        site: site,
        dateAcquired: dateAcquired,
        status: AVAILABLE
    };
    Asset created = check libraryApi->post("/assets", asset);
    io:println("Registered ", created.assetTag, " (", created.name, ").");
    return;
}

function updateAsset() returns error? {
    string tag = readRequired("Asset tag to update: ");
    Asset current = check libraryApi->get("/assets/" + encode(tag));
    printAssetDetail(current);
    io:println();
    io:println("Leave a field blank to keep its current value.");

    map<string> changes = {};
    addIfPresent(changes, "name", io:readln("New name        : "));
    addIfPresent(changes, "description", io:readln("New description : "));
    addIfPresent(changes, "site", io:readln("New site        : "));
    string? status = pickFrom("New status", ASSET_STATUSES, true);
    if status is string {
        changes["status"] = status;
    }
    if changes.length() == 0 {
        io:println("Nothing to change.");
        return;
    }
    Asset updated = check libraryApi->patch("/assets/" + encode(tag), changes);
    io:println("Asset updated.");
    printAssetDetail(updated);
    return;
}

function addIfPresent(map<string> changes, string fieldName, string value) {
    string trimmed = value.trim();
    if trimmed != "" {
        changes[fieldName] = trimmed;
    }
}

function deleteAsset() returns error? {
    string tag = readRequired("Asset tag to remove: ");
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
    string tag = readRequired("Asset tag             : ");
    json request = {
        borrower: readRequired("Borrower (student no.): "),
        dueDate: readDate("Due back (YYYY-MM-DD) : ", ())
    };
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/loan", request);
    Loan? loan = asset.currentLoan;
    if loan is Loan {
        io:println("Loan ", loan.loanId, " created for ", loan.borrower, ", due ", loan.dueDate, ".");
    }
    return;
}

function returnAsset() returns error? {
    string tag = readRequired("Asset tag: ");
    json emptyBody = {};
    Asset asset = check libraryApi->post("/assets/" + encode(tag) + "/return", emptyBody);
    io:println(asset.assetTag, " is back on the shelf and ", asset.status, ".");
    return;
}

function bookSpace() returns error? {
    string tag = readRequired("Asset tag (lab / room) : ");
    json request = {
        bookedBy: readRequired("Booked by              : "),
        startDate: readDate("From (YYYY-MM-DD)      : ", ()),
        endDate: readDate("To   (YYYY-MM-DD)      : ", ()),
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
    int action = subMenu("Schedules", ["List the schedules of an asset", "Add a schedule", "Remove a schedule"]);
    if action == 0 {
        return;
    }
    string tag = readRequired("Asset tag   : ");
    string base = "/assets/" + encode(tag) + "/schedules";

    if action == 1 {
        Asset asset = check libraryApi->get("/assets/" + encode(tag));
        if asset.schedules.length() == 0 {
            io:println("No schedules on this asset.");
        }
        printSchedules(asset);
        return;
    }
    if action == 3 {
        string scheduleId = readRequired("Schedule id : ");
        Asset asset = check libraryApi->delete(base + "/" + encode(scheduleId));
        io:println("Schedule removed.");
        printSchedules(asset);
        return;
    }
    string scheduleId = readRequired("Schedule id : ");
    string? scheduleType = pickFrom("Schedule type", SCHEDULE_TYPES, false);
    json schedule = {
        scheduleId: scheduleId,
        'type: scheduleType,
        dueDate: readDate("Due date (YYYY-MM-DD): ", ()),
        description: io:readln("Description : ").trim()
    };
    Asset asset = check libraryApi->post(base, schedule);
    io:println("Schedule added.");
    printSchedules(asset);
    return;
}

function manageComponents() returns error? {
    int action = subMenu("Components", ["List the components of an asset", "Add a component", "Remove a component"]);
    if action == 0 {
        return;
    }
    string tag = readRequired("Asset tag    : ");
    string base = "/assets/" + encode(tag) + "/components";

    if action == 1 {
        Component[] components = check libraryApi->get(base);
        printComponents(components);
        return;
    }
    if action == 3 {
        string compId = readRequired("Component id : ");
        Asset asset = check libraryApi->delete(base + "/" + encode(compId));
        io:println("Component removed. ", asset.components.length(), " remaining.");
        printComponents(asset.components);
        return;
    }
    json component = {
        compId: readRequired("Component id : "),
        name: readRequired("Name         : "),
        description: io:readln("Description  : ").trim()
    };
    Asset asset = check libraryApi->post(base, component);
    io:println("Component added. The asset now has ", asset.components.length(), " component(s).");
    printComponents(asset.components);
    return;
}

function manageWorkOrders() returns error? {
    int action = subMenu("Work orders and tasks", [
        "List the work orders of an asset",
        "Open a work order (fault report)",
        "Update / close a work order",
        "Add a task to a work order",
        "Remove a task from a work order"
    ]);
    if action == 0 {
        return;
    }
    string tag = readRequired("Asset tag  : ");
    string base = "/assets/" + encode(tag) + "/workorders";

    match action {
        1 => {
            WorkOrder[] orders = check libraryApi->get(base);
            printWorkOrders(orders);
        }
        2 => {
            json workOrder = {orderId: "", status: "OPEN", description: readRequired("Fault      : ")};
            Asset asset = check libraryApi->post(base, workOrder);
            WorkOrder opened = asset.workOrders[asset.workOrders.length() - 1];
            io:println("Opened work order ", opened.orderId, ". Asset is now ", asset.status, ".");
        }
        3 => {
            string orderId = readRequired("Order id   : ");
            string? status = pickFrom("New status", WORK_ORDER_STATUSES, false);
            json update = {status: status};
            Asset asset = check libraryApi->put(base + "/" + encode(orderId), update);
            io:println("Work order updated. Asset is now ", asset.status, ".");
        }
        4 => {
            string orderId = readRequired("Order id   : ");
            json task = {taskId: "", description: readRequired("Task       : ")};
            Asset asset = check libraryApi->post(base + "/" + encode(orderId) + "/tasks", task);
            io:println("Task added to ", orderId, ".");
            printWorkOrders(asset.workOrders);
        }
        5 => {
            string orderId = readRequired("Order id   : ");
            string taskId = readRequired("Task id    : ");
            Asset asset = check libraryApi->delete(base + "/" + encode(orderId) + "/tasks/" + encode(taskId));
            io:println("Task removed.");
            printWorkOrders(asset.workOrders);
        }
    }
    return;
}

function manageInstitutions() returns error? {
    int action = subMenu("Institutions and sites", [
        "List institutions",
        "Campus view - assets of one institution",
        "Register an institution",
        "Add a site / campus to an institution",
        "Remove an institution"
    ]);
    match action {
        1 => {
            Institution[] institutions = check libraryApi->get("/institutions");
            printInstitutions(institutions);
        }
        2 => {
            Institution? institution = check pickInstitution("Institution", false);
            if institution is Institution {
                Asset[] assets = check libraryApi->get("/institutions/" + encode(institution.institutionId)
                        + "/assets");
                printAssetTable(assets, institution.name);
            }
        }
        3 => {
            json institution = {
                institutionId: readRequired("Id (e.g. NIMT) : ").toUpperAscii(),
                name: readRequired("Full name      : "),
                sites: [readRequired("First site     : ")]
            };
            Institution added = check libraryApi->post("/institutions", institution);
            io:println("Registered ", added.name, ".");
        }
        4 => {
            Institution? institution = check pickInstitution("Institution", false);
            if institution is Institution {
                json payload = {site: readRequired("New site / campus : ")};
                Institution updated = check libraryApi->post("/institutions/"
                        + encode(institution.institutionId) + "/sites", payload);
                io:println(updated.name, " now has sites: ", string:'join(", ", ...updated.sites));
            }
        }
        5 => {
            Institution? institution = check pickInstitution("Institution to remove", false);
            if institution is Institution {
                Institution removed = check libraryApi->delete("/institutions/"
                        + encode(institution.institutionId));
                io:println("Removed ", removed.name, " from the listing.");
            }
        }
    }
    return;
}

// --------------------------------- pickers ---------------------------------

# Lets the user pick an institution from the live list on the server.
# Returns `()` when the user leaves the choice blank (only if `optional`).
function pickInstitution(string title, boolean optional) returns Institution?|error {
    Institution[] institutions = check libraryApi->get("/institutions");
    if institutions.length() == 0 {
        io:println("No institutions are registered yet.");
        return ();
    }
    string[] labels = from Institution institution in institutions
        select institution.institutionId + " - " + institution.name;
    int? index = pickIndex(title, labels, optional);
    return index is int ? institutions[index] : ();
}

# Lets the user pick one of the institution's sites, or type a new one.
function pickSite(Institution institution) returns string {
    string[] options = [...institution.sites, "Other (type a site name)"];
    int? index = pickIndex("Site / campus", options, false);
    if index is int && index < institution.sites.length() {
        return institution.sites[index];
    }
    return readRequired("Site / campus name: ");
}

function pickFrom(string title, string[] options, boolean optional) returns string? {
    int? index = pickIndex(title, options, optional);
    return index is int ? options[index] : ();
}

# Prints a numbered list and keeps asking until a valid number is entered.
# Returns the zero-based index, or `()` for a blank answer when `optional`.
function pickIndex(string title, string[] options, boolean optional) returns int? {
    io:println(title, ":");
    foreach int i in 0 ..< options.length() {
        io:println("   ", i + 1, ". ", options[i]);
    }
    string hint = optional ? " (Enter to skip)" : "";
    while true {
        string answer = io:readln("   Choose 1-" + options.length().toString() + hint + ": ").trim();
        if answer == "" && optional {
            return ();
        }
        int|error number = int:fromString(answer);
        if number is int && number >= 1 && number <= options.length() {
            return number - 1;
        }
        io:println("   Please enter a number between 1 and ", options.length(), ".");
    }
}

# Shows a numbered sub-menu with a "back" option and returns the chosen
# number (0 means back).
function subMenu(string title, string[] options) returns int {
    io:println("---- ", title, " ----");
    foreach int i in 0 ..< options.length() {
        io:println("  ", i + 1, ". ", options[i]);
    }
    io:println("  0. Back to main menu");
    while true {
        string answer = io:readln("Choose: ").trim();
        int|error number = int:fromString(answer);
        if number is int && number >= 0 && number <= options.length() {
            return number;
        }
        io:println("Please enter a number between 0 and ", options.length(), ".");
    }
}

// ---------------------------------- input ----------------------------------

function readRequired(string label) returns string {
    while true {
        string value = io:readln(label).trim();
        if value != "" {
            return value;
        }
        io:println("   This field is required.");
    }
}

# Reads a calendar date in YYYY-MM-DD form, re-asking until it is valid. A
# blank answer returns `default` when one is given.
function readDate(string label, string? default) returns string {
    while true {
        string value = io:readln(label).trim();
        if value == "" && default is string {
            return default;
        }
        if isValidDate(value) {
            return value;
        }
        io:println("   Please enter a real date in the form YYYY-MM-DD, e.g. 2026-11-02.");
    }
}

function isValidDate(string value) returns boolean {
    if value.length() != 10 {
        return false;
    }
    time:Utc|error parsed = time:utcFromString(value + "T00:00:00Z");
    return parsed is time:Utc;
}

function today() returns string {
    return time:utcToString(time:utcNow()).substring(0, 10);
}

function pause() {
    _ = io:readln("\nPress Enter to return to the menu...");
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
        printComponents(asset.components);
    }
    printSchedules(asset);
    if asset.workOrders.length() > 0 {
        printWorkOrders(asset.workOrders);
    }
}

function printComponents(Component[] components) {
    if components.length() == 0 {
        io:println("No components on this asset.");
        return;
    }
    io:println("Components   :");
    foreach Component component in components {
        io:println("   - ", fit(component.compId, 10), fit(component.name, 30), component.description);
    }
}

function printSchedules(Asset asset) {
    if asset.schedules.length() == 0 {
        return;
    }
    io:println("Schedules    :");
    foreach Schedule schedule in asset.schedules {
        string? endDate = schedule.endDate;
        string period = endDate is string ? schedule.dueDate + " -> " + endDate : schedule.dueDate;
        io:println("   - ", fit(schedule.scheduleId, 12), fit(schedule.'type, 14), fit(period, 26),
                schedule.description);
    }
}

function printWorkOrders(WorkOrder[] orders) {
    if orders.length() == 0 {
        io:println("No work orders on this asset.");
        return;
    }
    io:println("Work orders  :");
    foreach WorkOrder orderEntry in orders {
        io:println("   - ", fit(orderEntry.orderId, 12), fit(orderEntry.status, 14), orderEntry.description);
        foreach Task task in orderEntry.tasks {
            io:println("        * ", fit(task.taskId, 10), task.description);
        }
    }
}

function printInstitutions(Institution[] institutions) {
    io:println("  ", fit("ID", 10), fit("NAME", 52), "SITES");
    foreach Institution institution in institutions {
        io:println("  ", fit(institution.institutionId, 10), fit(institution.name, 52),
                string:'join(", ", ...institution.sites));
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
            "%" => {
                encoded += "%25";
            }
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
            "+" => {
                encoded += "%2B";
            }
            _ => {
                encoded += character;
            }
        }
    }
    return encoded;
}

# Prints a server-side failure in a way a user can act on: the HTTP status and
# the message from the uniform error body the API returns.
function report(error e) {
    if e is http:ApplicationResponseError {
        http:Detail detail = e.detail();
        anydata body = detail.body;
        string message = body.toString();
        if body is map<anydata> {
            anydata text = body["message"];
            if text is string {
                message = text;
            }
        }
        io:println("  ! Error ", detail.statusCode, ": ", message);
        return;
    }
    if e is http:ClientConnectorError {
        io:println("  ! Cannot reach the API at ", apiUrl, " - is the backend running?");
        return;
    }
    io:println("  ! ", e.message());
}
