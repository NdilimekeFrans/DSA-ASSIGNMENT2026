// ---------------------------------------------------------------------------
// Data store backed by SQLite (see db.bal for the connection and schema).
//
// Assets are keyed on their unique `assetTag` (the PRIMARY KEY of the `assets`
// table) and institutions on `institutionId`. Every function below loads the
// rows it needs, applies the business rules in Ballerina, and writes the result
// back with a parameterized SQL statement.
//
// Concurrency: the HTTP listener serves requests concurrently, so every
// read-modify-write sequence runs inside a `lock` block that touches the
// isolated `storeRevision` counter. Ballerina guarantees that lock blocks
// sharing an isolated variable never run at the same time, so the
// load -> change -> save steps of one request are atomic: two updates of the
// same asset can never interleave and lose each other's changes. Values that
// leave a lock are cloned, as the isolation rules require.
// ---------------------------------------------------------------------------

# Raised when the requested entity does not exist.
public type NotFoundError distinct error;

# Raised when an entity with the same unique key already exists.
public type ConflictError distinct error;

# Raised when the payload is syntactically valid but semantically wrong.
public type ValidationError distinct error;

# Number of write operations since start-up. Every writer increments it inside
# its `lock` block; sharing this one isolated variable is what makes those
# blocks mutually exclusive.
isolated int storeRevision = 0;

// ------------------------------ institutions -------------------------------

public isolated function listInstitutions() returns Institution[]|StoreError {
    return queryInstitutions(``);
}

public isolated function getInstitution(string institutionId) returns Institution|NotFoundError|StoreError {
    return loadInstitution(institutionId);
}

public isolated function addInstitution(Institution institution)
        returns Institution|ConflictError|ValidationError|StoreError {
    if institution.institutionId.trim() == "" || institution.name.trim() == "" {
        return error ValidationError("'institutionId' and 'name' are required");
    }
    string institutionId = institution.institutionId;
    string name = institution.name;
    lock {
        storeRevision += 1;
        boolean exists = check institutionExists(institutionId, name);
        if exists {
            return error ConflictError("Institution '" + institutionId + "' is already registered");
        }
        check saveInstitution(institution.clone());
        return institution.clone();
    }
}

public isolated function removeInstitution(string institutionId)
        returns Institution|NotFoundError|ConflictError|StoreError {
    lock {
        storeRevision += 1;
        Institution institution = check loadInstitution(institutionId);
        int owned = check countAssetsOwnedBy(institution.name);
        if owned > 0 {
            return error ConflictError("Institution '" + institution.name
                    + "' still has assets registered against it; remove or reassign them first");
        }
        check deleteInstitutionRow(institutionId);
        return institution.clone();
    }
}

# Adds a site/campus to an existing institution.
public isolated function addSite(string institutionId, string site)
        returns Institution|NotFoundError|ConflictError|StoreError {
    lock {
        storeRevision += 1;
        Institution found = check loadInstitution(institutionId);
        if found.sites.indexOf(site) != () {
            return error ConflictError("Site '" + site + "' is already listed for this institution");
        }
        found.sites.push(site);
        check saveInstitution(found);
        return found.clone();
    }
}

// --------------------------------- assets ----------------------------------

public isolated function listAssets() returns Asset[]|StoreError {
    return queryAssets(``);
}

public isolated function getAsset(string assetTag) returns Asset|NotFoundError|StoreError {
    return loadAsset(assetTag);
}

# Filters the catalogue. Any argument left as `()` is ignored, so the same
# function backs the global view, the campus view and the status view. The
# filtering happens in SQL; `lower()` makes the text comparisons
# case-insensitive.
public isolated function filterAssets(string? institution, string? site, AssetStatus? status)
        returns Asset[]|StoreError {
    return queryAssets(`WHERE (${institution} IS NULL OR lower(institution) = lower(${institution}))
                          AND (${site} IS NULL OR lower(site) = lower(${site}))
                          AND (${status} IS NULL OR status = ${status})`);
}

public isolated function addAsset(Asset asset) returns Asset|ConflictError|ValidationError|StoreError {
    check validateAsset(asset);
    string assetTag = asset.assetTag;
    lock {
        storeRevision += 1;
        boolean exists = check assetExists(assetTag);
        if exists {
            return error ConflictError("An asset with tag '" + assetTag + "' already exists");
        }
        check saveAsset(asset.clone());
        return asset.clone();
    }
}

isolated function validateAsset(Asset asset) returns ValidationError|StoreError? {
    if asset.assetTag.trim() == "" {
        return error ValidationError("'assetTag' must not be empty");
    }
    if asset.name.trim() == "" {
        return error ValidationError("'name' must not be empty");
    }
    if !isValidDate(asset.dateAcquired) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    boolean registered = check institutionIsRegistered(asset.institution);
    if !registered {
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
        returns Asset|NotFoundError|ValidationError|StoreError {
    Asset replacement = asset.clone();
    replacement.assetTag = assetTag;
    check validateAsset(replacement);
    lock {
        storeRevision += 1;
        boolean exists = check assetExists(assetTag);
        if !exists {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        check saveAsset(replacement.clone());
        return replacement.clone();
    }
}

# Partial update (PATCH). Only the fields present in the payload are applied.
# One SQL UPDATE does the work (see `updateAssetFields` in db.bal): fields the
# payload leaves out are bound as NULL and `COALESCE` keeps the stored value.
public isolated function patchAsset(string assetTag, AssetPatch patch)
        returns Asset|NotFoundError|ValidationError|StoreError {
    string? newDate = patch?.dateAcquired;
    if newDate is string && !isValidDate(newDate) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    string? newInstitution = patch?.institution;
    if newInstitution is string {
        boolean registered = check institutionIsRegistered(newInstitution);
        if !registered {
            return error ValidationError("'" + newInstitution + "' is not a registered institution");
        }
    }
    string? newName = patch?.name;
    string? newDescription = patch?.description;
    string? newSite = patch?.site;
    AssetStatus? newStatus = patch?.status;
    lock {
        storeRevision += 1;
        int updated = check updateAssetFields(assetTag, newName, newDescription, newInstitution,
                newSite, newStatus, newDate);
        if updated == 0 {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        return loadAsset(assetTag);
    }
}

public isolated function deleteAsset(string assetTag) returns Asset|NotFoundError|StoreError {
    lock {
        storeRevision += 1;
        Asset removed = check loadAsset(assetTag);
        check deleteAssetRow(assetTag);
        return removed.clone();
    }
}

// ------------------------------- components --------------------------------

public isolated function addComponent(string assetTag, Component component)
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
    if component.compId.trim() == "" || component.name.trim() == "" {
        return error ValidationError("'compId' and 'name' are required for a component");
    }
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
        foreach Component existing in found.components {
            if existing.compId == component.compId {
                return error ConflictError("Component '" + component.compId
                        + "' is already attached to asset '" + assetTag + "'");
            }
        }
        found.components.push(component.clone());
        check saveAsset(found);
        return found.clone();
    }
}

public isolated function removeComponent(string assetTag, string compId) returns Asset|NotFoundError|StoreError {
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
        Component[] remaining = from Component component in found.components
            where component.compId != compId
            select component;
        if remaining.length() == found.components.length() {
            return error NotFoundError("Asset '" + assetTag + "' has no component '" + compId + "'");
        }
        found.components = remaining;
        check saveAsset(found);
        return found.clone();
    }
}

// -------------------------------- schedules --------------------------------

public isolated function addSchedule(string assetTag, Schedule schedule)
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
    if schedule.scheduleId.trim() == "" {
        return error ValidationError("'scheduleId' is required for a schedule");
    }
    if !isValidDate(schedule.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
        foreach Schedule existing in found.schedules {
            if existing.scheduleId == schedule.scheduleId {
                return error ConflictError("Schedule '" + schedule.scheduleId
                        + "' already exists on asset '" + assetTag + "'");
            }
        }
        found.schedules.push(schedule.clone());
        check saveAsset(found);
        return found.clone();
    }
}

public isolated function removeSchedule(string assetTag, string scheduleId) returns Asset|NotFoundError|StoreError {
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
        check saveAsset(found);
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
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
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
    string scheduleId = check nextId("BKG");
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
        check saveAsset(found);
        return found.clone();
    }
}

// ------------------------------- work orders -------------------------------

public isolated function addWorkOrder(string assetTag, WorkOrder workOrder)
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
    if workOrder.description.trim() == "" {
        return error ValidationError("'description' is required for a work order");
    }
    string generated = check nextId("WO");
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
        check saveAsset(found);
        return found.clone();
    }
}

public isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderUpdate update)
        returns Asset|NotFoundError|StoreError {
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
        check saveAsset(found);
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
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
    if task.description.trim() == "" {
        return error ValidationError("'description' is required for a task");
    }
    string generated = check nextId("T");
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
            check saveAsset(found);
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

public isolated function removeTask(string assetTag, string orderId, string taskId)
        returns Asset|NotFoundError|StoreError {
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
            check saveAsset(found);
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

// ---------------------------------- loans ----------------------------------

public isolated function loanAsset(string assetTag, LoanRequest request)
        returns Asset|NotFoundError|ConflictError|ValidationError|StoreError {
    if request.borrower.trim() == "" {
        return error ValidationError("'borrower' is required");
    }
    if !isValidDate(request.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    string loanId = check nextId("LN");
    string loanDate = today();
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
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
        check saveAsset(found);
        return found.clone();
    }
}

public isolated function returnAsset(string assetTag) returns Asset|NotFoundError|ConflictError|StoreError {
    string returnDate = today();
    lock {
        storeRevision += 1;
        Asset found = check loadAsset(assetTag);
        Loan? loan = found.currentLoan;
        if loan is () || found.status != LOANED_OUT {
            return error ConflictError("Asset '" + assetTag + "' is not currently on loan");
        }
        loan.returnedDate = returnDate;
        found.currentLoan = ();
        found.status = AVAILABLE;
        check saveAsset(found);
        return found.clone();
    }
}

// ------------------------- maintenance / overdue ---------------------------

# Every maintenance, servicing or inspection schedule whose due date has passed.
public isolated function overdueSchedules() returns OverdueEntry[]|StoreError {
    string now = today();
    Asset[] assets = check listAssets();
    OverdueEntry[] entries = [];
    foreach Asset asset in assets {
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
    return entries;
}

# Every asset still on loan past its due date.
public isolated function overdueLoans() returns OverdueLoan[]|StoreError {
    string now = today();
    Asset[] assets = check listAssets();
    OverdueLoan[] entries = [];
    foreach Asset asset in assets {
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
    return entries;
}
