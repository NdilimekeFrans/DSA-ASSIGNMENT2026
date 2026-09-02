// ---------------------------------------------------------------------------
// Client-side view of the API contract.
//
// The client is a separate package with its own copy of the resource
// representations: it is an independent process that only knows the service
// through its published JSON contract, which is exactly the loose coupling a
// distributed system is supposed to have.
// ---------------------------------------------------------------------------

public enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

public enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

public enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED"
}

public type Component record {|
    string compId;
    string name;
    string description = "";
|};

public type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string description = "";
    string? endDate = ();
    string? bookedBy = ();
|};

public type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    string openedDate = "";
    string? closedDate = ();
    Task[] tasks = [];
|};

public type Loan record {|
    string loanId;
    string borrower;
    string loanDate;
    string dueDate;
    string? returnedDate = ();
|};

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

public type Institution record {|
    string institutionId;
    string name;
    string[] sites = [];
|};

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

public type OverdueLoan record {|
    string assetTag;
    string name;
    string institution;
    string borrower;
    string dueDate;
    int daysOverdue;
|};
