// ---------------------------------------------------------------------------
// In-memory data store.
//
// Assets live in a `map<Asset>` keyed on the unique `assetTag`, giving O(1)
// lookup, insert and delete on the natural business key. Institutions live in a
// `table<Institution> key(institutionId)` which enforces key uniqueness at the
// language level.
//
// Both variables are declared `isolated` and every access happens inside a
// `lock` block, so the store is safe under the concurrent requests the HTTP
// listener serves. Values crossing the lock boundary are cloned, which keeps
// callers from mutating stored state by holding on to a reference.
// ---------------------------------------------------------------------------

# Raised when the requested entity does not exist.
public type NotFoundError distinct error;

# Raised when an entity with the same unique key already exists.
public type ConflictError distinct error;

# Raised when the payload is syntactically valid but semantically wrong.
public type ValidationError distinct error;

isolated map<Asset> assetStore = {};

isolated table<Institution> key(institutionId) institutionStore = table [];

// ------------------------------ institutions -------------------------------

public isolated function listInstitutions() returns Institution[] {
    lock {
        return institutionStore.toArray().clone();
    }
}

public isolated function getInstitution(string institutionId) returns Institution|NotFoundError {
    lock {
        Institution? found = institutionStore[institutionId];
        if found is () {
            return error NotFoundError("No institution registered with id '" + institutionId + "'");
        }
        return found.clone();
    }
}

public isolated function addInstitution(Institution institution) returns Institution|ConflictError|ValidationError {
    if institution.institutionId.trim() == "" || institution.name.trim() == "" {
        return error ValidationError("'institutionId' and 'name' are required");
    }
    lock {
        if institutionStore.hasKey(institution.institutionId) {
            return error ConflictError("Institution '" + institution.institutionId + "' is already registered");
        }
        institutionStore.add(institution.clone());
        return institution.clone();
    }
}

public isolated function removeInstitution(string institutionId) returns Institution|NotFoundError|ConflictError {
    Institution institution = check getInstitution(institutionId);
    lock {
        foreach Asset asset in assetStore {
            if asset.institution == institution.name {
                return error ConflictError("Institution '" + institution.name
                        + "' still has assets registered against it; remove or reassign them first");
            }
        }
    }
    lock {
        Institution removed = institutionStore.remove(institutionId);
        return removed.clone();
    }
}

# Adds a site/campus to an existing institution.
public isolated function addSite(string institutionId, string site) returns Institution|NotFoundError|ConflictError {
    lock {
        Institution? found = institutionStore[institutionId];
        if found is () {
            return error NotFoundError("No institution registered with id '" + institutionId + "'");
        }
        if found.sites.indexOf(site) != () {
            return error ConflictError("Site '" + site + "' is already listed for this institution");
        }
        found.sites.push(site);
        return found.clone();
    }
}

isolated function institutionIsRegistered(string name) returns boolean {
    lock {
        foreach Institution institution in institutionStore {
            if institution.name == name {
                return true;
            }
        }
        return false;
    }
}

// --------------------------------- assets ----------------------------------

public isolated function listAssets() returns Asset[] {
    lock {
        return assetStore.toArray().clone();
    }
}

public isolated function getAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        return found.clone();
    }
}

# Filters the catalogue. Any argument left as `()` is ignored, so the same
# function backs the global view, the campus view and the status view.
public isolated function filterAssets(string? institution, string? site, AssetStatus? status)
        returns Asset[] {
    lock {
        Asset[] results = [];
        foreach Asset asset in assetStore {
            if institution is string && !equalsIgnoreCase(asset.institution, institution) {
                continue;
            }
            if site is string && !equalsIgnoreCase(asset.site, site) {
                continue;
            }
            if status is AssetStatus && asset.status != status {
                continue;
            }
            results.push(asset);
        }
        return results.clone();
    }
}

isolated function equalsIgnoreCase(string a, string b) returns boolean {
    return a.toLowerAscii() == b.toLowerAscii();
}

public isolated function addAsset(Asset asset) returns Asset|ConflictError|ValidationError {
    ValidationError? invalid = validateAsset(asset);
    if invalid is ValidationError {
        return invalid;
    }
    lock {
        if assetStore.hasKey(asset.assetTag) {
            return error ConflictError("An asset with tag '" + asset.assetTag + "' already exists");
        }
        assetStore[asset.assetTag] = asset.clone();
        return asset.clone();
    }
}

isolated function validateAsset(Asset asset) returns ValidationError? {
    if asset.assetTag.trim() == "" {
        return error ValidationError("'assetTag' must not be empty");
    }
    if asset.name.trim() == "" {
        return error ValidationError("'name' must not be empty");
    }
    if !isValidDate(asset.dateAcquired) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    if !institutionIsRegistered(asset.institution) {
        return error ValidationError("'" + asset.institution
                + "' is not a registered institution; register it via POST /library/institutions first");
    }
    foreach Schedule schedule in asset.schedules {
        if !isValidDate(schedule.dueDate) {
            return error ValidationError("Schedule '" + schedule.scheduleId
                    + "' has an invalid dueDate '" + schedule.dueDate + "'");
        }
    }
    return ();
}

# Full replacement (idempotent PUT). The tag in the path wins over the tag in
# the payload so the unique key can never be changed by an update.
public isolated function replaceAsset(string assetTag, Asset asset)
        returns Asset|NotFoundError|ValidationError {
    Asset replacement = asset.clone();
    replacement.assetTag = assetTag;
    ValidationError? invalid = validateAsset(replacement);
    if invalid is ValidationError {
        return invalid;
    }
    lock {
        if !assetStore.hasKey(assetTag) {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        assetStore[assetTag] = replacement.clone();
        return replacement.clone();
    }
}

# Partial update (PATCH). Only the fields present in the payload are applied.
public isolated function patchAsset(string assetTag, AssetPatch patch)
        returns Asset|NotFoundError|ValidationError {
    string? newDate = patch?.dateAcquired;
    if newDate is string && !isValidDate(newDate) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    string? newInstitution = patch?.institution;
    if newInstitution is string && !institutionIsRegistered(newInstitution) {
        return error ValidationError("'" + newInstitution + "' is not a registered institution");
    }
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        AssetPatch changes = patch.clone();
        string? name = changes?.name;
        if name is string {
            found.name = name;
        }
        string? description = changes?.description;
        if description is string {
            found.description = description;
        }
        string? institution = changes?.institution;
        if institution is string {
            found.institution = institution;
        }
        string? site = changes?.site;
        if site is string {
            found.site = site;
        }
        AssetStatus? status = changes?.status;
        if status is AssetStatus {
            found.status = status;
        }
        string? dateAcquired = changes?.dateAcquired;
        if dateAcquired is string {
            found.dateAcquired = dateAcquired;
        }
        return found.clone();
    }
}

public isolated function deleteAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? removed = assetStore.removeIfHasKey(assetTag);
        if removed is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        return removed.clone();
    }
}

// ------------------------------- components --------------------------------

public isolated function addComponent(string assetTag, Component component)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if component.compId.trim() == "" || component.name.trim() == "" {
        return error ValidationError("'compId' and 'name' are required for a component");
    }
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach Component existing in found.components {
            if existing.compId == component.compId {
                return error ConflictError("Component '" + component.compId
                        + "' is already attached to asset '" + assetTag + "'");
            }
        }
        found.components.push(component.clone());
        return found.clone();
    }
}

public isolated function removeComponent(string assetTag, string compId) returns Asset|NotFoundError {
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Component[] remaining = from Component component in found.components
            where component.compId != compId
            select component;
        if remaining.length() == found.components.length() {
            return error NotFoundError("Asset '" + assetTag + "' has no component '" + compId + "'");
        }
        found.components = remaining;
        return found.clone();
    }
}

// -------------------------------- schedules --------------------------------

public isolated function addSchedule(string assetTag, Schedule schedule)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if schedule.scheduleId.trim() == "" {
        return error ValidationError("'scheduleId' is required for a schedule");
    }
    if !isValidDate(schedule.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach Schedule existing in found.schedules {
            if existing.scheduleId == schedule.scheduleId {
                return error ConflictError("Schedule '" + schedule.scheduleId
                        + "' already exists on asset '" + assetTag + "'");
            }
        }
        found.schedules.push(schedule.clone());
        return found.clone();
    }
}

public isolated function removeSchedule(string assetTag, string scheduleId) returns Asset|NotFoundError {
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Schedule[] remaining = from Schedule schedule in found.schedules
            where schedule.scheduleId != scheduleId
            select schedule;
        if remaining.length() == found.schedules.length() {
            return error NotFoundError("Asset '" + assetTag + "' has no schedule '" + scheduleId + "'");
        }
        found.schedules = remaining;
        if found.status == OCCUPIED && !hasActiveBooking(found) {
            found.status = AVAILABLE;
        }
        return found.clone();
    }
}

isolated function hasActiveBooking(Asset asset) returns boolean {
    foreach Schedule schedule in asset.schedules {
        if schedule.'type == BOOKING {
            string end = schedule.endDate ?: schedule.dueDate;
            if !isPast(end) {
                return true;
            }
        }
    }
    return false;
}

# Books a lab or meeting room for a date range. The booking is stored as a
# `BOOKING` schedule so that a single collection carries both servicing and
# occupancy information for the resource.
public isolated function bookAsset(string assetTag, BookingRequest request)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if request.bookedBy.trim() == "" {
        return error ValidationError("'bookedBy' is required");
    }
    if !isValidDate(request.startDate) || !isValidDate(request.endDate) {
        return error ValidationError("'startDate' and 'endDate' must be calendar dates in YYYY-MM-DD form");
    }
    int|error span = daysBetween(request.startDate, request.endDate);
    if span is error || span <= 0 {
        return error ValidationError("'endDate' must be after 'startDate'");
    }
    string scheduleId = nextId("BKG");
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        if found.status == UNDER_MAINTENANCE || found.status == DISPOSED {
            return error ConflictError("Asset '" + assetTag + "' is " + found.status
                    + " and cannot be booked");
        }
        BookingRequest booking = request.clone();
        foreach Schedule schedule in found.schedules {
            if schedule.'type != BOOKING {
                continue;
            }
            string otherEnd = schedule.endDate ?: schedule.dueDate;
            boolean|error clash = rangesOverlap(booking.startDate, booking.endDate,
                    schedule.dueDate, otherEnd);
            if clash is boolean && clash {
                return error ConflictError("Asset '" + assetTag + "' is already booked from "
                        + schedule.dueDate + " to " + otherEnd);
            }
        }
        found.schedules.push({
            scheduleId: scheduleId,
            'type: BOOKING,
            dueDate: booking.startDate,
            endDate: booking.endDate,
            bookedBy: booking.bookedBy,
            description: booking.description
        });
        found.status = OCCUPIED;
        return found.clone();
    }
}

// ------------------------------- work orders -------------------------------

public isolated function addWorkOrder(string assetTag, WorkOrder workOrder)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if workOrder.description.trim() == "" {
        return error ValidationError("'description' is required for a work order");
    }
    string generated = nextId("WO");
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        WorkOrder candidate = workOrder.clone();
        if candidate.orderId.trim() == "" {
            candidate.orderId = generated;
        }
        foreach WorkOrder existing in found.workOrders {
            if existing.orderId == candidate.orderId {
                return error ConflictError("Work order '" + candidate.orderId
                        + "' already exists on asset '" + assetTag + "'");
            }
        }
        if candidate.openedDate == "" {
            candidate.openedDate = today();
        }
        found.workOrders.push(candidate);
        found.status = UNDER_MAINTENANCE;
        return found.clone();
    }
}

public isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderUpdate update)
        returns Asset|NotFoundError {
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        WorkOrderUpdate change = update.clone();
        boolean matched = false;
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            matched = true;
            workOrder.status = change.status;
            string? description = change?.description;
            if description is string {
                workOrder.description = description;
            }
            if change.status == CLOSED {
                workOrder.closedDate = today();
            }
        }
        if !matched {
            return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
        }
        if !hasOpenWorkOrder(found) && found.status == UNDER_MAINTENANCE {
            found.status = AVAILABLE;
        }
        return found.clone();
    }
}

isolated function hasOpenWorkOrder(Asset asset) returns boolean {
    foreach WorkOrder workOrder in asset.workOrders {
        if workOrder.status != CLOSED {
            return true;
        }
    }
    return false;
}

public isolated function addTask(string assetTag, string orderId, Task task)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if task.description.trim() == "" {
        return error ValidationError("'description' is required for a task");
    }
    string generated = nextId("T");
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Task candidate = task.clone();
        if candidate.taskId.trim() == "" {
            candidate.taskId = generated;
        }
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            foreach Task existing in workOrder.tasks {
                if existing.taskId == candidate.taskId {
                    return error ConflictError("Task '" + candidate.taskId
                            + "' already exists on work order '" + orderId + "'");
                }
            }
            workOrder.tasks.push(candidate);
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

public isolated function removeTask(string assetTag, string orderId, string taskId)
        returns Asset|NotFoundError {
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            Task[] remaining = from Task task in workOrder.tasks
                where task.taskId != taskId
                select task;
            if remaining.length() == workOrder.tasks.length() {
                return error NotFoundError("Work order '" + orderId + "' has no task '" + taskId + "'");
            }
            workOrder.tasks = remaining;
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

// ---------------------------------- loans ----------------------------------

public isolated function loanAsset(string assetTag, LoanRequest request)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if request.borrower.trim() == "" {
        return error ValidationError("'borrower' is required");
    }
    if !isValidDate(request.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    string loanId = nextId("LN");
    string loanDate = today();
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        if found.status != AVAILABLE {
            return error ConflictError("Asset '" + assetTag + "' is currently " + found.status
                    + " and cannot be loaned out");
        }
        LoanRequest loanRequest = request.clone();
        found.currentLoan = {
            loanId: loanId,
            borrower: loanRequest.borrower,
            loanDate: loanDate,
            dueDate: loanRequest.dueDate
        };
        found.status = LOANED_OUT;
        return found.clone();
    }
}

public isolated function returnAsset(string assetTag) returns Asset|NotFoundError|ConflictError {
    string returnDate = today();
    lock {
        Asset? found = assetStore[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Loan? loan = found.currentLoan;
        if loan is () || found.status != LOANED_OUT {
            return error ConflictError("Asset '" + assetTag + "' is not currently on loan");
        }
        loan.returnedDate = returnDate;
        found.currentLoan = ();
        found.status = AVAILABLE;
        return found.clone();
    }
}

// ------------------------- maintenance / overdue ---------------------------

# Every maintenance, servicing or inspection schedule whose due date has passed.
public isolated function overdueSchedules() returns OverdueEntry[] {
    string now = today();
    lock {
        OverdueEntry[] entries = [];
        foreach Asset asset in assetStore {
            if asset.status == DISPOSED {
                continue;
            }
            foreach Schedule schedule in asset.schedules {
                if schedule.'type == BOOKING {
                    continue;
                }
                int|error elapsed = daysBetween(schedule.dueDate, now);
                if elapsed is error || elapsed <= 0 {
                    continue;
                }
                entries.push({
                    assetTag: asset.assetTag,
                    name: asset.name,
                    institution: asset.institution,
                    site: asset.site,
                    status: asset.status,
                    scheduleId: schedule.scheduleId,
                    scheduleType: schedule.'type,
                    dueDate: schedule.dueDate,
                    daysOverdue: elapsed,
                    description: schedule.description
                });
            }
        }
        return entries.clone();
    }
}

# Every asset still on loan past its due date.
public isolated function overdueLoans() returns OverdueLoan[] {
    string now = today();
    lock {
        OverdueLoan[] entries = [];
        foreach Asset asset in assetStore {
            Loan? loan = asset.currentLoan;
            if loan is () {
                continue;
            }
            int|error elapsed = daysBetween(loan.dueDate, now);
            if elapsed is error || elapsed <= 0 {
                continue;
            }
            entries.push({
                assetTag: asset.assetTag,
                name: asset.name,
                institution: asset.institution,
                borrower: loan.borrower,
                dueDate: loan.dueDate,
                daysOverdue: elapsed
            });
        }
        return entries.clone();
    }
}
