import ballerina/http;
import ballerina/log;

// ---------------------------------------------------------------------------
// RESTful backend for the Distributed Library and Resource Management System.
//
//   Resource-oriented URIs      /library/assets/{assetTag}/schedules/{id}
//   Correct verb semantics      GET safe, PUT/DELETE idempotent, POST creates
//   Uniform error envelope      ErrorResponse { code, message, resource }
//   Correct status codes        200 / 201 / 204 / 400 / 404 / 409
//
// A second service on the same listener serves the single-page web dashboard
// so that the API and the UI share one origin.
// ---------------------------------------------------------------------------

configurable int port = 8080;

listener http:Listener apiListener = new (port);

# Seeds the store with the institutions of higher learning registered with the
# Ministry, plus a couple of demonstration assets.
function init() returns error? {
    Institution[] seedInstitutions = [
        {
            institutionId: "NUST",
            name: "Namibia University of Science and Technology",
            sites: ["Main Campus - Innovation Lab", "Main Campus - Library", "Ongwediva Campus"]
        },
        {
            institutionId: "UNAM",
            name: "University of Namibia",
            sites: ["Main Campus - Windhoek", "Oshakati Campus"]
        },
        {
            institutionId: "IUM",
            name: "International University of Management",
            sites: ["Dorado Campus"]
        }
    ];
    foreach Institution institution in seedInstitutions {
        Institution|error added = addInstitution(institution);
        if added is error {
            return added;
        }
    }

    Asset[] seedAssets = [
        {
            assetTag: "NUST-LIB-3DP-001",
            name: "Pro-Series 3D Printer",
            description: "High-precision laboratory printer for simulation and prototype development.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Innovation Lab",
            status: AVAILABLE,
            dateAcquired: "2024-03-10",
            components: [
                {compId: "C101", name: "High-Torque Stepper Motor", description: "Main motor for X-axis movement."}
            ],
            schedules: [
                {
                    scheduleId: "SCH-882",
                    'type: MAINTENANCE,
                    dueDate: "2026-09-01",
                    description: "Quarterly calibration and nozzle cleaning."
                }
            ],
            workOrders: []
        },
        {
            assetTag: "NUST-LIB-BK-1042",
            name: "Distributed Systems: Theory and Applications",
            description: "Ghosh & Ghosh, 1st edition. Reference copy, short loan.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Library",
            status: AVAILABLE,
            dateAcquired: "2023-08-01"
        },
        {
            assetTag: "UNAM-LAB-ROOM-07",
            name: "Networks Laboratory 7",
            description: "Thirty-seat teaching laboratory, bookable per session.",
            institution: "University of Namibia",
            site: "Main Campus - Windhoek",
            status: AVAILABLE,
            dateAcquired: "2019-01-15"
        },
        {
            assetTag: "UNAM-IT-LT-0333",
            name: "ThinkPad L14 Loan Laptop",
            description: "Student loan laptop, fourteen day maximum loan period.",
            institution: "University of Namibia",
            site: "Oshakati Campus",
            status: AVAILABLE,
            dateAcquired: "2025-02-20",
            schedules: [
                {
                    scheduleId: "SCH-104",
                    'type: SERVICING,
                    dueDate: "2026-06-30",
                    description: "Annual battery health check and re-imaging."
                }
            ]
        }
    ];
    foreach Asset asset in seedAssets {
        Asset|error added = addAsset(asset);
        if added is error {
            return added;
        }
    }
    log:printInfo("Library API started", port = port, assets = seedAssets.length());
    return ();
}

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Accept"]
    }
}
service /library on apiListener {

    // ----------------------------- institutions ----------------------------

    # Lists every registered institution.
    resource function get institutions() returns Institution[] {
        return listInstitutions();
    }

    # Looks up a single institution.
    resource function get institutions/[string institutionId]() returns Institution|ApiError {
        Institution|NotFoundError result = getInstitution(institutionId);
        return result is Institution ? result : toApiError(result, institutionId);
    }

    # Registers a new institution with the Ministry listing.
    resource function post institutions(@http:Payload Institution institution)
            returns http:Created|ApiError {
        Institution|error result = addInstitution(institution);
        if result is error {
            return toApiError(result, institution.institutionId);
        }
        http:Created created = {
            body: result,
            headers: {"Location": string `/library/institutions/${result.institutionId}`}
        };
        return created;
    }

    # Adds a site/campus to an institution.
    resource function post institutions/[string institutionId]/sites(@http:Payload record {|string site;|} payload)
            returns Institution|ApiError {
        Institution|error result = addSite(institutionId, payload.site);
        return result is Institution ? result : toApiError(result, institutionId);
    }

    # Removes an institution from the listing. Refused while it still owns assets.
    resource function delete institutions/[string institutionId]() returns Institution|ApiError {
        Institution|error result = removeInstitution(institutionId);
        return result is Institution ? result : toApiError(result, institutionId);
    }

    // -------------------------------- assets -------------------------------

    # Global view of every asset in the Ministry, with optional filtering by
    # institution, site and status:
    # `GET /library/assets?institution=University%20of%20Namibia&status=AVAILABLE`
    resource function get assets(string? institution = (), string? site = (), string? status = ())
            returns Asset[]|ApiError {
        AssetStatus? statusFilter = ();
        if status is string {
            if status is AssetStatus {
                statusFilter = status;
            } else {
                return badRequest("'" + status + "' is not a valid status. Expected one of "
                        + "AVAILABLE, LOANED_OUT, OCCUPIED, UNDER_MAINTENANCE, DISPOSED", "status");
            }
        }
        return filterAssets(institution, site, statusFilter);
    }

    # Campus view: every asset belonging to one institution, optionally narrowed
    # to a single site.
    resource function get institutions/[string institutionId]/assets(string? site = ())
            returns Asset[]|ApiError {
        Institution|NotFoundError institution = getInstitution(institutionId);
        if institution is NotFoundError {
            return toApiError(institution, institutionId);
        }
        return filterAssets(institution.name, site, ());
    }

    # Looks up one asset by its unique tag.
    resource function get assets/[string assetTag]() returns Asset|ApiError {
        Asset|NotFoundError result = getAsset(assetTag);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Creates a new asset.
    resource function post assets(@http:Payload Asset asset) returns http:Created|ApiError {
        Asset|error result = addAsset(asset);
        if result is error {
            return toApiError(result, asset.assetTag);
        }
        http:Created created = {
            body: result,
            headers: {"Location": string `/library/assets/${result.assetTag}`}
        };
        return created;
    }

    # Full replacement of an asset (idempotent).
    resource function put assets/[string assetTag](@http:Payload Asset asset) returns Asset|ApiError {
        Asset|error result = replaceAsset(assetTag, asset);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Partial update of an asset.
    resource function patch assets/[string assetTag](@http:Payload AssetPatch patch) returns Asset|ApiError {
        Asset|error result = patchAsset(assetTag, patch);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Removes an asset from the register.
    resource function delete assets/[string assetTag]() returns Asset|ApiError {
        Asset|NotFoundError result = deleteAsset(assetTag);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    // ------------------------------ components -----------------------------

    resource function get assets/[string assetTag]/components() returns Component[]|ApiError {
        Asset|NotFoundError result = getAsset(assetTag);
        return result is Asset ? result.components : toApiError(result, assetTag);
    }

    resource function post assets/[string assetTag]/components(@http:Payload Component component)
            returns Asset|ApiError {
        Asset|error result = addComponent(assetTag, component);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    resource function delete assets/[string assetTag]/components/[string compId]() returns Asset|ApiError {
        Asset|NotFoundError result = removeComponent(assetTag, compId);
        return result is Asset ? result : toApiError(result, compId);
    }

    // ------------------------------- schedules -----------------------------

    resource function get assets/[string assetTag]/schedules() returns Schedule[]|ApiError {
        Asset|NotFoundError result = getAsset(assetTag);
        return result is Asset ? result.schedules : toApiError(result, assetTag);
    }

    resource function post assets/[string assetTag]/schedules(@http:Payload Schedule schedule)
            returns Asset|ApiError {
        Asset|error result = addSchedule(assetTag, schedule);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    resource function delete assets/[string assetTag]/schedules/[string scheduleId]() returns Asset|ApiError {
        Asset|NotFoundError result = removeSchedule(assetTag, scheduleId);
        return result is Asset ? result : toApiError(result, scheduleId);
    }

    // ------------------------------ work orders ----------------------------

    resource function get assets/[string assetTag]/workorders() returns WorkOrder[]|ApiError {
        Asset|NotFoundError result = getAsset(assetTag);
        return result is Asset ? result.workOrders : toApiError(result, assetTag);
    }

    # Opens a work order against a faulty resource.
    resource function post assets/[string assetTag]/workorders(@http:Payload WorkOrder workOrder)
            returns Asset|ApiError {
        Asset|error result = addWorkOrder(assetTag, workOrder);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Updates or closes a work order.
    resource function put assets/[string assetTag]/workorders/[string orderId](@http:Payload WorkOrderUpdate update)
            returns Asset|ApiError {
        Asset|NotFoundError result = updateWorkOrder(assetTag, orderId, update);
        return result is Asset ? result : toApiError(result, orderId);
    }

    # Adds a sub-task such as "replace screen" to a work order.
    resource function post assets/[string assetTag]/workorders/[string orderId]/tasks(@http:Payload Task task)
            returns Asset|ApiError {
        Asset|error result = addTask(assetTag, orderId, task);
        return result is Asset ? result : toApiError(result, orderId);
    }

    resource function delete assets/[string assetTag]/workorders/[string orderId]/tasks/[string taskId]()
            returns Asset|ApiError {
        Asset|NotFoundError result = removeTask(assetTag, orderId, taskId);
        return result is Asset ? result : toApiError(result, taskId);
    }

    // --------------------------- loans and bookings ------------------------

    # Loans a book, laptop or thin client to a borrower.
    resource function post assets/[string assetTag]/loan(@http:Payload LoanRequest request)
            returns Asset|ApiError {
        Asset|error result = loanAsset(assetTag, request);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Returns a loaned asset to the shelf.
    resource function post assets/[string assetTag]/'return() returns Asset|ApiError {
        Asset|error result = returnAsset(assetTag);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    # Books a lab or meeting room for a date range.
    resource function post assets/[string assetTag]/bookings(@http:Payload BookingRequest request)
            returns Asset|ApiError {
        Asset|error result = bookAsset(assetTag, request);
        return result is Asset ? result : toApiError(result, assetTag);
    }

    // ------------------------ maintenance dashboards -----------------------

    # Every maintenance/servicing schedule whose due date has passed.
    resource function get maintenance/overdue() returns OverdueEntry[] {
        return overdueSchedules();
    }

    # Every asset still on loan past its due date.
    resource function get loans/overdue() returns OverdueLoan[] {
        return overdueLoans();
    }

    # Liveness probe.
    resource function get health() returns record {|string status; int assets;|} {
        return {status: "UP", assets: listAssets().length()};
    }
}

// ---------------------------------------------------------------------------
// Error handling: the store raises typed errors, the service translates them
// into the matching HTTP status with a uniform body. Anything unrecognised
// becomes a 500 rather than leaking a stack trace to the caller.
// ---------------------------------------------------------------------------

public type ApiError http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError;

isolated function toApiError(error e, string 'resource) returns ApiError {
    if e is NotFoundError {
        http:NotFound notFound = {body: {code: "NOT_FOUND", message: e.message(), 'resource: 'resource}};
        return notFound;
    }
    if e is ConflictError {
        http:Conflict conflict = {body: {code: "CONFLICT", message: e.message(), 'resource: 'resource}};
        return conflict;
    }
    if e is ValidationError {
        http:BadRequest badRequestResponse = {
            body: {code: "VALIDATION_FAILED", message: e.message(), 'resource: 'resource}
        };
        return badRequestResponse;
    }
    log:printError("Unhandled error while serving request", e, 'resource = 'resource);
    http:InternalServerError serverError = {
        body: {code: "INTERNAL_ERROR", message: "The request could not be processed", 'resource: 'resource}
    };
    return serverError;
}

isolated function badRequest(string message, string 'resource) returns http:BadRequest {
    http:BadRequest response = {body: {code: "VALIDATION_FAILED", message: message, 'resource: 'resource}};
    return response;
}
