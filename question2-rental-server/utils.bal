import ballerina/time;

// ---------------------------------------------------------------------------
// Date arithmetic and identifier generation for the rental service.
// Calendar dates are converted to epoch-day integers, which makes the two
// pieces of booking logic trivial and exact: counting nights and detecting
// overlapping stays.
// ---------------------------------------------------------------------------

const int SECONDS_PER_DAY = 86400;

public isolated function toEpochDay(string date) returns int|error {
    time:Utc utc = check time:utcFromString(date + "T00:00:00Z");
    return utc[0] / SECONDS_PER_DAY;
}

public isolated function isValidDate(string date) returns boolean {
    int|error day = toEpochDay(date);
    return day is int;
}

# Number of nights between a check-in and a check-out date.
public isolated function nightsBetween(string checkIn, string checkOut) returns int|error {
    return check toEpochDay(checkOut) - check toEpochDay(checkIn);
}

# Half-open overlap test: a stay ending on the day another begins is fine.
public isolated function staysOverlap(string aIn, string aOut, string bIn, string bOut)
        returns boolean|error {
    int aStart = check toEpochDay(aIn);
    int aEnd = check toEpochDay(aOut);
    int bStart = check toEpochDay(bIn);
    int bEnd = check toEpochDay(bOut);
    return aStart < bEnd && bStart < aEnd;
}

public isolated function today() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

isolated function pad2(int value) returns string {
    return value < 10 ? "0" + value.toString() : value.toString();
}

isolated int sequence = 1000;

# Generates identifiers such as `PROP-1001` or `BKG-1042`.
public isolated function nextId(string prefix) returns string {
    lock {
        sequence += 1;
        return prefix + "-" + sequence.toString();
    }
}

# Rounds a money amount to two decimal places, so totals never carry the
# floating-point tail of a multiplication.
public isolated function round2(float amount) returns float {
    return amount.round(2);
}
