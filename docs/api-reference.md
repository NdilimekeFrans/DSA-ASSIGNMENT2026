# REST API reference — Question 1

Base URL: `http://localhost:8080/library`
All requests and responses are `application/json`.

Every example below can be pasted straight into a terminal while the backend is
running (`cd question1-library-api && bal run`).

---

## Conventions

**Status codes**

| Code | Meaning |
|---|---|
| `200 OK` | The request succeeded |
| `201 Created` | An entity was created; `Location` points at it |
| `400 Bad Request` | The payload failed validation |
| `404 Not Found` | No entity with that key |
| `409 Conflict` | The request conflicts with current state |
| `500 Internal Server Error` | Unexpected failure |

**Error envelope**

```json
{
  "code": "NOT_FOUND",
  "message": "No asset found with tag 'NUST-LIB-9999'",
  "resource": "NUST-LIB-9999"
}
```

`code` is one of `VALIDATION_FAILED`, `NOT_FOUND`, `CONFLICT`, `INTERNAL_ERROR`.

**Asset status values** — `AVAILABLE`, `LOANED_OUT`, `OCCUPIED`,
`UNDER_MAINTENANCE`, `DISPOSED`.
**Schedule types** — `MAINTENANCE`, `SERVICING`, `INSPECTION`, `BOOKING`.
**Work order status** — `OPEN`, `IN_PROGRESS`, `CLOSED`.
**Dates** — ISO-8601 calendar dates, `YYYY-MM-DD`.

---

## Assets

### List all assets

```bash
curl http://localhost:8080/library/assets
```

Optional query parameters, combinable: `institution`, `site`, `status`.

```bash
curl "http://localhost:8080/library/assets?institution=University%20of%20Namibia&status=AVAILABLE"
curl "http://localhost:8080/library/assets?site=Main%20Campus%20-%20Library"
```

An unknown status value returns `400`:

```json
{ "code": "VALIDATION_FAILED",
  "message": "'BROKEN' is not a valid status. Expected one of AVAILABLE, LOANED_OUT, OCCUPIED, UNDER_MAINTENANCE, DISPOSED",
  "resource": "status" }
```

### Campus view

```bash
curl http://localhost:8080/library/institutions/UNAM/assets
curl "http://localhost:8080/library/institutions/UNAM/assets?site=Oshakati%20Campus"
```

### Look up one asset

```bash
curl http://localhost:8080/library/assets/NUST-LIB-3DP-001
```

```json
{
  "assetTag": "NUST-LIB-3DP-001",
  "name": "Pro-Series 3D Printer",
  "description": "High-precision laboratory printer for simulation and prototype development.",
  "institution": "Namibia University of Science and Technology",
  "site": "Main Campus - Innovation Lab",
  "status": "AVAILABLE",
  "dateAcquired": "2024-03-10",
  "components": [
    { "compId": "C101", "name": "High-Torque Stepper Motor",
      "description": "Main motor for X-axis movement." }
  ],
  "schedules": [
    { "scheduleId": "SCH-882", "type": "MAINTENANCE", "dueDate": "2026-09-01",
      "description": "Quarterly calibration and nozzle cleaning.",
      "endDate": null, "bookedBy": null }
  ],
  "workOrders": [],
  "currentLoan": null
}
```

### Create an asset

```bash
curl -X POST http://localhost:8080/library/assets \
  -H "Content-Type: application/json" \
  -d '{
        "assetTag": "NUST-LIB-TC-2210",
        "name": "HP Thin Client t640",
        "description": "Reading-room thin client.",
        "institution": "Namibia University of Science and Technology",
        "site": "Main Campus - Library",
        "status": "AVAILABLE",
        "dateAcquired": "2026-02-01"
      }'
```

`201 Created`, `Location: /library/assets/NUST-LIB-TC-2210`. A repeat of the
same call returns `409`; an unregistered institution returns `400`.

### Replace an asset (idempotent)

```bash
curl -X PUT http://localhost:8080/library/assets/NUST-LIB-TC-2210 \
  -H "Content-Type: application/json" \
  -d '{ "assetTag": "ignored", "name": "HP Thin Client t640",
        "description": "Moved to the postgraduate reading room.",
        "institution": "Namibia University of Science and Technology",
        "site": "Main Campus - Library", "status": "AVAILABLE",
        "dateAcquired": "2026-02-01" }'
```

The tag in the path always wins, so an update can never change the unique key.

### Partial update

```bash
curl -X PATCH http://localhost:8080/library/assets/NUST-LIB-TC-2210 \
  -H "Content-Type: application/json" \
  -d '{ "status": "UNDER_MAINTENANCE" }'
```

### Delete an asset

```bash
curl -X DELETE http://localhost:8080/library/assets/NUST-LIB-TC-2210
```

Returns the removed asset, so the caller can undo or log it.

---

## Components

```bash
curl http://localhost:8080/library/assets/NUST-LIB-3DP-001/components

curl -X POST http://localhost:8080/library/assets/NUST-LIB-3DP-001/components \
  -H "Content-Type: application/json" \
  -d '{ "compId": "C102", "name": "Heated Print Bed",
        "description": "Aluminium bed with PEI sheet." }'

curl -X DELETE http://localhost:8080/library/assets/NUST-LIB-3DP-001/components/C102
```

A duplicate `compId` on the same asset returns `409`.

---

## Schedules

```bash
curl http://localhost:8080/library/assets/NUST-LIB-3DP-001/schedules

curl -X POST http://localhost:8080/library/assets/NUST-LIB-3DP-001/schedules \
  -H "Content-Type: application/json" \
  -d '{ "scheduleId": "SCH-901", "type": "SERVICING",
        "dueDate": "2026-12-01",
        "description": "Annual belt tension and firmware update." }'

curl -X DELETE http://localhost:8080/library/assets/NUST-LIB-3DP-001/schedules/SCH-901
```

An invalid `dueDate` returns `400`; a duplicate `scheduleId` returns `409`.

---

## Work orders and tasks

```bash
# Open one — an empty orderId asks the server to allocate it
curl -X POST http://localhost:8080/library/assets/NUST-LIB-3DP-001/workorders \
  -H "Content-Type: application/json" \
  -d '{ "orderId": "", "status": "OPEN", "description": "Nozzle heat-bed failure" }'

# Add a sub-task
curl -X POST http://localhost:8080/library/assets/NUST-LIB-3DP-001/workorders/WO-1001/tasks \
  -H "Content-Type: application/json" \
  -d '{ "taskId": "", "description": "Check thermal sensor connectivity." }'

# Close it
curl -X PUT http://localhost:8080/library/assets/NUST-LIB-3DP-001/workorders/WO-1001 \
  -H "Content-Type: application/json" \
  -d '{ "status": "CLOSED" }'

curl -X DELETE http://localhost:8080/library/assets/NUST-LIB-3DP-001/workorders/WO-1001/tasks/T-1002
```

Opening a work order moves the asset to `UNDER_MAINTENANCE`; closing the last
open one returns it to `AVAILABLE`.

---

## Loans

```bash
curl -X POST http://localhost:8080/library/assets/NUST-LIB-BK-1042/loan \
  -H "Content-Type: application/json" \
  -d '{ "borrower": "220012345", "dueDate": "2026-09-30" }'

curl -X POST http://localhost:8080/library/assets/NUST-LIB-BK-1042/return
```

A second loan while the asset is out returns `409`:

```json
{ "code": "CONFLICT",
  "message": "Asset 'NUST-LIB-BK-1042' is currently LOANED_OUT and cannot be loaned out",
  "resource": "NUST-LIB-BK-1042" }
```

---

## Room and lab bookings

```bash
curl -X POST http://localhost:8080/library/assets/UNAM-LAB-ROOM-07/bookings \
  -H "Content-Type: application/json" \
  -d '{ "bookedBy": "Dr Shikongo", "startDate": "2026-11-02",
        "endDate": "2026-11-06",
        "description": "DSA612S practical sessions." }'
```

The booking is stored as a `BOOKING` schedule and the asset becomes `OCCUPIED`.
An overlapping range returns `409`; a range ending on or before its start
returns `400`. A booking that starts on the day another ends is accepted.

---

## Maintenance dashboards

```bash
curl http://localhost:8080/library/maintenance/overdue
curl http://localhost:8080/library/loans/overdue
```

```json
[
  { "assetTag": "UNAM-IT-LT-0333",
    "name": "ThinkPad L14 Loan Laptop",
    "institution": "University of Namibia",
    "site": "Oshakati Campus",
    "status": "AVAILABLE",
    "scheduleId": "SCH-104",
    "scheduleType": "SERVICING",
    "dueDate": "2026-06-30",
    "daysOverdue": 64,
    "description": "Annual battery health check and re-imaging." }
]
```

`BOOKING` schedules are excluded — a room being occupied is not a maintenance
failure — and `DISPOSED` assets are skipped.

---

## Institutions

```bash
curl http://localhost:8080/library/institutions
curl http://localhost:8080/library/institutions/NUST

curl -X POST http://localhost:8080/library/institutions \
  -H "Content-Type: application/json" \
  -d '{ "institutionId": "NIMT",
        "name": "Namibian Institute of Mining and Technology",
        "sites": ["Arandis Campus"] }'

curl -X POST http://localhost:8080/library/institutions/NIMT/sites \
  -H "Content-Type: application/json" \
  -d '{ "site": "Tsumeb Campus" }'

curl -X DELETE http://localhost:8080/library/institutions/NIMT
```

Removing an institution that still owns assets returns `409`.

---

## Health

```bash
curl http://localhost:8080/library/health
```

```json
{ "status": "UP", "assets": 4 }
```
