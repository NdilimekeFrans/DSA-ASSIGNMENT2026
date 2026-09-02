// ---------------------------------------------------------------------------
// Domain model for the Distributed Library and Resource Management System.
//
// Every record below is a plain `anydata` record so that it can be used
// directly as an HTTP payload binding target (automatic JSON <-> record
// conversion) and safely cloned in and out of the isolated data store.
// ---------------------------------------------------------------------------

# Lifecycle state of a tracked resource.
public enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

# Kind of schedule attached to an asset.
public enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

# Lifecycle state of a work order raised against a faulty asset.
public enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED"
}

# A replaceable part of a complex asset (e.g. the stepper motor of a printer).
public type Component record {|
    string compId;
    string name;
    string description = "";
|};

# A dated entry against an asset: maintenance, servicing, inspection or a
# room/lab booking. `dueDate` doubles as the start date for BOOKING entries and
# `endDate` is then the check-out date.
public type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string description = "";
    string? endDate = ();
    string? bookedBy = ();
|};

# A single unit of work inside a work order (e.g. "replace screen").
public type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

# A repair/servicing job raised against an asset.
public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    string openedDate = "";
    string? closedDate = ();
    Task[] tasks = [];
|};

# An active or historical loan of an asset to a borrower.
public type Loan record {|
    string loanId;
    string borrower;
    string loanDate;
    string dueDate;
    string? returnedDate = ();
|};

# The aggregate root of the system. `assetTag` is the unique key used by the
# in-memory data store.
public type Asset record {|
    string assetTag;
    string name;
    string description = "";
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
    Loan? currentLoan = ();
|};

# Partial update payload used by `PATCH /library/assets/{assetTag}`. Every
# field is optional; absent fields are left untouched.
public type AssetPatch record {|
    string name?;
    string description?;
    string institution?;
    string site?;
    AssetStatus status?;
    string dateAcquired?;
|};

# A registered institution of higher learning. Stored in a `table` keyed on
# `institutionId`.
public type Institution record {|
    readonly string institutionId;
    string name;
    string[] sites = [];
|};

# Request body for loaning an asset out.
public type LoanRequest record {|
    string borrower;
    string dueDate;
|};

# Request body for booking a lab or meeting room for a date range.
public type BookingRequest record {|
    string bookedBy;
    string startDate;
    string endDate;
    string description = "";
|};

# Request body used to change the status of a work order.
public type WorkOrderUpdate record {|
    WorkOrderStatus status;
    string description?;
|};

# Uniform error body returned for every non-2xx response.
public type ErrorResponse record {|
    string code;
    string message;
    string 'resource?;
|};

# An asset whose maintenance/servicing schedule has elapsed. Returned by the
# overdue dashboard.
public type OverdueEntry record {|
    string assetTag;
    string name;
    string institution;
    string site;
    AssetStatus status;
    string scheduleId;
    ScheduleType scheduleType;
    string dueDate;
    int daysOverdue;
    string description;
|};

# An asset that is on loan past its due date.
public type OverdueLoan record {|
    string assetTag;
    string name;
    string institution;
    string borrower;
    string dueDate;
    int daysOverdue;
|};
