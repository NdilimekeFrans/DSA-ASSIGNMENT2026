# Design notes

This document records the decisions behind the two systems and why each was
made. It assumes the reader has the code open alongside it.

---

## 1. Two systems, two communication styles

The assignment deliberately pairs the same class of problem — a shared catalogue
with mutating clients — with two different interaction mechanisms, and the
contrast is the interesting part.

| | Question 1 (REST) | Question 2 (gRPC) |
|---|---|---|
| Contract | URIs, verbs and JSON, described in the README | `rental.proto`, compiled to code |
| Coupling | Late: the client parses JSON it recognises | Early: both ends share generated types |
| Transport | HTTP/1.1, text | HTTP/2, binary Protocol Buffers |
| Streaming | Not used; each call is a request/response | Client-side and server-side streams |
| Best suited to | Public, long-lived, cacheable interfaces | Internal, chatty, high-volume service calls |

Both are forms of inter-process communication over the network stack, and both
are *remote invocation* in the sense of the course: the caller writes something
that looks like a local call and the runtime turns it into messages. The
difference is where the contract lives — in documentation for REST, in a
compiled artefact for gRPC — and what happens when the two sides drift apart.
The REST client keeps working when the server adds a field; the gRPC client has
to be regenerated when the contract changes, but it cannot silently misread a
payload.

---

## 2. Question 1 — Library and Resource Management System

### 2.1 Resource model

`Asset` is the aggregate root and `assetTag` is its natural key: it is already
unique across the Ministry, it is printed on the physical label, and it is what
a librarian types. Using it as the map key rather than a generated surrogate id
means a caller never has to look up an internal identifier first.

Components, schedules, work orders and the current loan are *inside* the asset
rather than in separate collections. A component has no meaning without its
asset and is never queried independently, so a single document keeps the store
simple and every read consistent. Tasks nest one level deeper inside their work
order for the same reason.

Bookings of rooms and labs are stored as schedules with `type = BOOKING` and a
`endDate`. That way one collection answers both questions a member of staff
asks about a room — *when is it being serviced?* and *when is it occupied?* —
and the overdue dashboard only has to skip the `BOOKING` entries.

### 2.2 The data store

`map<Asset>` keyed on `assetTag` gives O(1) create, look-up, update and delete
on the business key, and `hasKey` makes uniqueness a one-line check rather than
a scan.

Institutions use `table<Institution> key(institutionId)` instead. A table
enforces key uniqueness in the language itself — `add` fails on a duplicate —
which is exactly what a registry of institutions needs, and it demonstrates the
second storage abstraction the brief mentions.

Every stored value crosses the `lock` boundary through `clone()`. Without it a
caller would hold a reference into the store and could mutate it later without
going through the API, which under concurrent requests would produce corruption
that is very hard to reproduce.

### 2.3 Concurrency

The HTTP listener serves requests on many threads, so the store must be safe
under concurrent mutation. Ballerina's answer is `isolated` variables plus
`lock`: the compiler refuses to build code that reads or writes an isolated
variable outside a lock, so the discipline is checked at compile time rather
than trusted. All locking lives in `store.bal`; the service layer never locks,
which keeps the critical sections short and easy to reason about.

### 2.4 API design

The endpoints follow the RESTful principles from Week 7:

* **Resources, not procedures.** `POST /assets/{tag}/loan` acts on a resource;
  there is no `/doLoan?action=…`.
* **Verb semantics.** `GET` never mutates. `PUT` replaces the whole asset and
  is *idempotent* — replaying it after a timeout, which is exactly what a flaky
  network causes, leaves the same state. `PATCH` carries only the changed
  fields. `DELETE` is idempotent in effect: the second call reports 404 but
  changes nothing.
* **Status codes carry meaning.** `201` with a `Location` header on creation,
  `400` for a payload the server cannot accept, `404` for a missing entity,
  `409` when the request conflicts with current state (a duplicate tag, a
  double loan, an overlapping booking).
* **One error envelope.** Every failure returns `{code, message, resource}`, so
  both clients render errors with the same three lines of code.

The store raises three typed errors — `NotFoundError`, `ConflictError`,
`ValidationError` — and `toApiError()` is the single place that maps them onto
HTTP. Business rules therefore never mention status codes, and a second
protocol could be put in front of the same store without touching it.

### 2.5 Business rules worth noting

* An asset can only be loaned when it is `AVAILABLE`, which makes a double loan
  a `409` rather than a silently lost record.
* Room bookings use a half-open interval: a guest checking out on the 6th does
  not clash with one checking in on the 6th.
* Opening a work order moves the asset to `UNDER_MAINTENANCE`; closing the last
  open order returns it to `AVAILABLE`. Status is derived from what is
  happening to the asset instead of being set by hand and drifting.
* An institution cannot be removed while it still owns assets — the alternative
  is orphaned records whose owner no longer exists.

### 2.6 The web console

The browser interface is one static HTML file with no build step and no
framework. It is served from the same listener as the API, so it shares an
origin and needs no proxy, and it uses only `fetch` against the documented
endpoints — it has no privileged access of any kind. Anything it can do, the
command-line client can do too. CORS is enabled on the API anyway so the page
can be opened from elsewhere during a demonstration.

---

## 3. Question 2 — Rental Accommodation System

### 3.1 The contract

`rental.proto` defines eight RPCs across three of the four gRPC styles. The
choice of style per operation follows the shape of the data:

* `create_users` is **client streaming** because a batch of profiles is many
  messages and one answer. Streaming them avoids building the whole batch in
  memory on either side, and the single response makes the batch feel atomic to
  the caller.
* `list_available_properties` is **server streaming** because the catalogue can
  be long and the Guest can start reading the first listing before the last one
  has been selected.
* Everything else is a single question with a single answer, so a **simple**
  RPC is the honest description.

Two details are worth defending. First, dates are `string` in ISO-8601 form
rather than `google.protobuf.Timestamp`: the system reasons in whole nights, a
timestamp would invite a timezone bug at every boundary, and the messages stay
readable in `grpcurl`. Second, `update_property` treats empty strings and zeros
as "leave unchanged" instead of using proto3 `optional` field presence — one
message then serves both a price change and a full edit, at the cost of not
being able to blank a field, which no Host needs to do.

### 3.2 Server-side state

Properties, users and confirmed bookings are held in maps keyed on their ids;
each Guest's cart is a map from `guest_id` to a list of pending stays. The same
`isolated` + `lock` discipline as Question 1 applies, and for the same reason:
the gRPC listener is concurrent, so two Guests can be confirming bookings for
the same property at the same instant.

### 3.3 Booking: cart, then commit

`book_property` and `confirm_booking` are deliberately separate, and the
validation is deliberately repeated in both.

`book_property` validates the request — the property exists, it is available,
the dates parse, the check-out follows the check-in, the party fits, no
confirmed stay overlaps — and puts an item in the cart. It commits nothing.

`confirm_booking` re-runs the availability and overlap checks before writing.
Between the two calls another Guest may have confirmed the same dates, so a
check performed at cart time is only a courtesy; the check that counts is the
one inside the operation that writes. The cost is priced at confirmation time
too, from the property's current rate × the number of nights, so a Host's price
change cannot be dodged by leaving something in a cart.

A partly successful confirmation is a normal outcome rather than an error: the
items that succeeded are confirmed and cleared, the ones that clashed stay in
the cart with a reason in `rejected`, so the Guest can adjust the dates and try
again without re-entering everything.

### 3.4 Failure handling

The service answers with an unsuccessful *response message* — `success: false`
plus an explanation — rather than a gRPC status error for anything the caller
could reasonably ask: an unknown id, a listing that is unavailable, dates that
do not make sense. `search_property` returning "Not Available" is explicitly
required by the brief, and the same reasoning covers the rest. gRPC errors are
kept for genuine faults, which keeps the client's error path small and stops a
normal outcome from being logged as a failure.

---

## 4. Limitations and future work

Both systems keep state in memory, so a restart loses it — the brief calls for
maps or tables, but a production deployment would put a replicated store behind
the same interfaces, which is why all state access is already confined to one
file per system.

Neither service authenticates its callers. Question 1 trusts the `borrower`
field and Question 2 trusts `host_id`; a real deployment would need tokens and
would check that the Host in the token owns the property being edited, which is
the point where the security topics of Week 9 would be applied.

Finally, neither system is replicated. Both are single processes, so they are
distributed in the sense of separating clients from services across the network,
but not yet in the sense of tolerating the loss of a node. Adding that would
mean externalising the state and putting several instances behind a load
balancer — a change the current structure does not obstruct, but does not
attempt.
