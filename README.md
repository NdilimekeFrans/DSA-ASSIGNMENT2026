# DSA612S Assignment 1

Two distributed systems written in Ballerina, each driven from a command-line
menu.

| Folder | What it is |
|---|---|
| `question1-library-api` | REST backend for the Library and Resource Management System (port 8080) |
| `question1-library-client` | Menu-driven CLI client for the REST API |
| `question2-rental-server` | gRPC server for the Rental Accommodation System (port 9090) |
| `question2-rental-client` | Menu-driven CLI client for the gRPC service |
| `proto/rental.proto` | gRPC contract for Question 2 |
| `docs/` | Design notes and the REST API reference |

Requires Ballerina Swan Lake (tested with 2201.13.5).

## Running Question 1 (REST)

Open two terminals.

```bash
# terminal 1 - start the backend
cd question1-library-api
bal run

# terminal 2 - start the menu client
cd question1-library-client
bal run
```

The client shows a numbered main menu. Type a number and press Enter. Options
11-14 open a sub-menu; `0` goes back. Institutions, sites, statuses and
schedule types are picked from numbered lists, and dates must be `YYYY-MM-DD`.
Invalid input is asked again rather than sent to the server.

Seeded data to try: assets `NUST-LIB-3DP-001`, `NUST-LIB-BK-1042`,
`UNAM-LAB-ROOM-07`, `UNAM-IT-LT-0333`; institutions `NUST`, `UNAM`, `IUM`.

The backend also serves a browser console at <http://localhost:8080/>.

Unit tests: `cd question1-library-api && bal test`

## Running Question 2 (gRPC)

```bash
# terminal 1 - start the server
cd question2-rental-server
bal run

# terminal 2 - start the menu client
cd question2-rental-client
bal run
```

Option `1` runs a scripted demonstration of all eight RPCs, including both
streaming calls. Options 2-9 run each RPC on its own.

Seeded data to try: hosts `HOST-001`, `HOST-002`; guest `GUEST-001`;
properties `PROP-001` to `PROP-004` (`PROP-004` is unavailable).

## Tips

* Start the server before its client. The Question 1 client offers to retry if
  the API is not up yet.
* If `bal build` / `bal run` seems stuck, it is usually resolving dependencies
  online; `bal run --offline` uses the local cache.
* Question 1 stores its data in `question1-library-api/library.db` (SQLite). It is
  created and seeded on the first run; delete the file to start again from the
  seed data. Question 2 keeps its state in memory.
