import ballerina/time;

// ---------------------------------------------------------------------------
// Small date and identifier helpers shared by the service and the data store.
// Dates are exchanged as ISO-8601 calendar dates ("YYYY-MM-DD") which keeps the
// JSON payloads readable; internally they are converted to epoch-day integers
// so that comparisons and night counts are trivial.
// ---------------------------------------------------------------------------

const int SECONDS_PER_DAY = 86400;

# Converts an ISO-8601 calendar date to the number of days since the epoch.
#
# + date - date in `YYYY-MM-DD` form
# + return - epoch day number, or an error if the date cannot be parsed
public isolated function toEpochDay(string date) returns int|error {
    time:Utc utc = check time:utcFromString(date + "T00:00:00Z");
    return utc[0] / SECONDS_PER_DAY;
}

# Returns `true` when the given string is a well formed calendar date.
public isolated function isValidDate(string date) returns boolean {
    int|error day = toEpochDay(date);
    return day is int;
}

# Number of whole days from `'start` to `end` (negative when `end` is earlier).
public isolated function daysBetween(string 'start, string end) returns int|error {
    return check toEpochDay(end) - check toEpochDay('start);
}

# Today's date in `YYYY-MM-DD` form, in UTC.
public isolated function today() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

isolated function pad2(int value) returns string {
    return value < 10 ? "0" + value.toString() : value.toString();
}

# `true` when `date` lies strictly before today.
public isolated function isPast(string date) returns boolean {
    int|error diff = daysBetween(date, today());
    return diff is int && diff > 0;
}

# Half-open overlap test for two date ranges: `[aStart, aEnd)` and
# `[bStart, bEnd)`. A check-out on the same day another guest checks in is
# therefore *not* a clash.
public isolated function rangesOverlap(string aStart, string aEnd, string bStart, string bEnd)
        returns boolean|error {
    int as = check toEpochDay(aStart);
    int ae = check toEpochDay(aEnd);
    int bs = check toEpochDay(bStart);
    int be = check toEpochDay(bEnd);
    return as < be && bs < ae;
}

isolated int sequence = 1000;

# Generates a readable, monotonically increasing identifier such as `LN-1001`.
public isolated function nextId(string prefix) returns string {
    lock {
        sequence += 1;
        return prefix + "-" + sequence.toString();
    }
}
