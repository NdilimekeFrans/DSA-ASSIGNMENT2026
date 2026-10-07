import ballerina/grpc;
import ballerina/io;
import ballerina/time;

// ---------------------------------------------------------------------------
// Ministry of Tourism - Rental Accommodation System (gRPC client).
//
// The client exercises every operation in the contract, including the two
// streaming ones:
//   create_users               client-side streaming
//   list_available_properties  server-side streaming
//
// Option 1 runs the whole story end to end, which is the quickest way to see
// the system work; the remaining options drive each RPC on its own. Every
// prompt is checked before the request is sent, so a typing mistake asks
// again instead of aborting the operation.
// ---------------------------------------------------------------------------

configurable string serverUrl = "http://localhost:9090";

final RentalServiceClient rentalClient = check new (serverUrl);

final string[] & readonly ROLES = ["HOST", "GUEST"];
final string[] & readonly PROPERTY_TYPES = ["APARTMENT", "GUESTHOUSE", "LODGE", "CAMPSITE", "HOUSE"];
final string[] & readonly PROPERTY_STATUSES = ["AVAILABLE", "UNAVAILABLE"];

public function main() {
    io:println();
    io:println("=========================================================");
    io:println(" Ministry of Tourism - Rental Accommodation System");
    io:println(" gRPC client connected to ", serverUrl);
    io:println("=========================================================");
    io:println(" Seeded accounts: HOST-001, HOST-002 (hosts), GUEST-001 (guest)");
    io:println(" Seeded listings: PROP-001 .. PROP-004");

    while true {
        printMenu();
        string choice = io:readln("Select an option: ").trim();
        io:println();
        if choice == "0" {
            io:println("Goodbye.");
            return;
        }
        if choice == "" {
            continue;
        }
        error? outcome = dispatch(choice);
        if outcome is error {
            io:println("  ! ", describe(outcome));
        }
        pause();
    }
}

function printMenu() {
    io:println();
    io:println("========================= MAIN MENU =====================");
    io:println(" 1. Run the full demonstration (all eight operations)");
    io:println("   -- Users --");
    io:println(" 2. Create user profiles        create_users (client streaming)");
    io:println("   -- Host --");
    io:println(" 3. Add a property              add_property");
    io:println(" 4. Update a property           update_property");
    io:println(" 5. Remove a property           remove_property");
    io:println("   -- Guest --");
    io:println(" 6. List available properties   list_available_properties (server streaming)");
    io:println(" 7. Search for a property       search_property");
    io:println(" 8. Add a stay to the cart      book_property");
    io:println(" 9. Confirm the booking cart    confirm_booking");
    io:println(" 0. Exit");
    io:println("=========================================================");
}

function dispatch(string choice) returns error? {
    match choice {
        "1" => {
            return runDemonstration();
        }
        "2" => {
            return createUsersInteractive();
        }
        "3" => {
            return addPropertyInteractive();
        }
        "4" => {
            return updatePropertyInteractive();
        }
        "5" => {
            return removePropertyInteractive();
        }
        "6" => {
            return listPropertiesInteractive();
        }
        "7" => {
            return searchPropertyInteractive();
        }
        "8" => {
            return bookPropertyInteractive();
        }
        "9" => {
            return confirmBookingInteractive();
        }
    }
    io:println("Unknown option '", choice, "'. Please choose a number from the menu.");
    return;
}

// ---------------------------- guided demonstration --------------------------

function runDemonstration() returns error? {
    // A per-run suffix keeps the demo repeatable against a long-running server.
    string suffix = uniqueSuffix();
    string hostId = "HOST-" + suffix;
    string guestId = "GUEST-" + suffix;

    banner("1. create_users - streaming three profiles to the server");
    User[] profiles = [
        {user_id: hostId, name: "Johanna Amutenya", email: "johanna@namib-stays.na", role: "HOST", phone: "+264 81 700 1000"},
        {user_id: guestId, name: "Thomas Kambwale", email: "thomas@example.na", role: "GUEST", phone: "+264 81 700 2000"},
        {user_id: "", name: "Nobody", email: "nobody@example.na", role: "TOURIST", phone: ""}
    ];
    CreateUsersResponse batch = check streamUsers(profiles);
    io:println("  created  : ", batch.created_count, " -> ", batch.created_user_ids.toString());
    io:println("  rejected : ", batch.rejected_count, "   <- the third profile has an invalid role");
    foreach string failure in batch.errors {
        io:println("      - ", failure);
    }

    banner("2. add_property - the new Host registers a listing");
    AddPropertyResponse added = check rentalClient->add_property({
        host_id: hostId,
        name: "Namib Desert Chalet",
        location: "Sesriem",
        region: "Hardap",
        property_type: "LODGE",
        price_per_night: 1450.0,
        status: "AVAILABLE",
        max_guests: 4,
        description: "Self-catering chalet at the gateway to Sossusvlei."
    });
    io:println("  ", added.message);
    if !added.success {
        return error("the demonstration listing could not be created: " + added.message);
    }
    string propertyId = added.property_id;
    io:println("  property_id = ", propertyId);

    banner("3. list_available_properties - the server streams the catalogue");
    int listed = check streamProperties({region: "", location: "", min_price: 0.0, max_price: 0.0,
            guests: 0, check_in: "", check_out: ""});
    io:println("  ", listed, " listing(s) streamed back.");

    banner("4. search_property - one hit and one miss");
    SearchPropertyResponse hit = check rentalClient->search_property({property_id: propertyId});
    io:println("  ", propertyId, " -> ", hit.message);
    SearchPropertyResponse miss = check rentalClient->search_property({property_id: "PROP-DOES-NOT-EXIST"});
    io:println("  PROP-DOES-NOT-EXIST -> ", miss.message);

    banner("5. update_property - the Host drops the nightly price");
    UpdatePropertyResponse updated = check rentalClient->update_property({
        property_id: propertyId,
        host_id: hostId,
        price_per_night: 1195.0,
        name: "",
        location: "",
        region: "",
        property_type: "",
        status: "",
        max_guests: 0,
        description: ""
    });
    io:println("  ", updated.message);
    Property? revised = updated?.property;
    if revised is Property {
        io:println("  new price = N$", revised.price_per_night, " per night");
    }

    banner("6. book_property - the Guest puts two stays in the cart");
    BookPropertyResponse first = check rentalClient->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: "2026-12-18",
        check_out: "2026-12-23",
        guests: 2
    });
    io:println("  stay 1 : ", first.message, " (", first.nights, " nights, estimate N$",
            first.estimated_total, ")");

    BookPropertyResponse invalid = check rentalClient->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: "2026-12-30",
        check_out: "2026-12-27",
        guests: 2
    });
    io:println("  stay 2 : ", invalid.message, "   <- server-side date validation");

    banner("7. confirm_booking - validate, price and commit the cart");
    ConfirmBookingResponse confirmed = check rentalClient->confirm_booking({
        guest_id: guestId,
        cart_item_id: ""
    });
    io:println("  ", confirmed.message);
    printBookings(confirmed.bookings);
    io:println("  grand total = N$", confirmed.grand_total);

    banner("8. book_property again - the dates are no longer free");
    BookPropertyResponse clash = check rentalClient->book_property({
        guest_id: "GUEST-001",
        property_id: propertyId,
        check_in: "2026-12-20",
        check_out: "2026-12-24",
        guests: 2
    });
    io:println("  ", clash.message, "   <- overlap detected");

    banner("9. remove_property - and the Host's remaining listings come back");
    RemovePropertyResponse removed = check rentalClient->remove_property({
        property_id: propertyId,
        host_id: hostId
    });
    io:println("  ", removed.message);
    io:println("  remaining listings for this Host in Hardap: ",
            removed.remaining_properties.length());
    io:println();
    io:println("  (The listing still carries a confirmed stay, so the server refuses to");
    io:println("   remove it - that is the expected outcome of this last step.)");
    io:println();
    io:println("  Demo accounts created: ", hostId, " (host) and ", guestId, " (guest).");
    return;
}

function banner(string title) {
    io:println();
    io:println("--- ", title, " ---");
}

function uniqueSuffix() returns string {
    int seconds = time:utcNow()[0];
    return (seconds % 1000000).toString();
}

// ------------------------------ streaming helpers --------------------------

# Client-side streaming: open the stream, send every profile, complete it, then
# read the single summary the server sends back.
function streamUsers(User[] profiles) returns CreateUsersResponse|error {
    Create_usersStreamingClient streamingClient = check rentalClient->create_users();
    foreach User user in profiles {
        check streamingClient->sendUser(user);
    }
    check streamingClient->complete();

    CreateUsersResponse? response = check streamingClient->receiveCreateUsersResponse();
    if response is () {
        return error("the server closed the stream without sending a summary");
    }
    return response;
}

# Server-side streaming: consume the stream one message at a time and print
# each listing as it arrives. The stream closes itself once the server has
# sent the last listing.
function streamProperties(ListPropertiesRequest request) returns int|error {
    stream<Property, grpc:Error?> properties = check rentalClient->list_available_properties(request);
    int count = 0;
    io:println("  ", fit("ID", 12), fit("NAME", 30), fit("LOCATION", 16), fit("REGION", 16),
            fit("TYPE", 12), fit("SLEEPS", 8), "PRICE/NIGHT");
    check from Property property in properties
        do {
            count += 1;
            io:println("  ", fit(property.property_id, 12), fit(property.name, 30),
                    fit(property.location, 16), fit(property.region, 16),
                    fit(property.property_type, 12), fit(property.max_guests.toString(), 8),
                    "N$", property.price_per_night);
        };
    if count == 0 {
        io:println("  (no listings match those filters)");
    }
    return count;
}

// ----------------------------- interactive options -------------------------

function createUsersInteractive() returns error? {
    User[] profiles = [];
    io:println("Enter user profiles one after another. Leave the name blank to finish");
    io:println("and stream the whole batch to the server.");
    while true {
        io:println();
        string name = io:readln("Name (blank to finish)       : ").trim();
        if name == "" {
            break;
        }
        string userId = io:readln("Id (blank to auto-generate)  : ").trim();
        string email = io:readln("Email                        : ").trim();
        string phone = io:readln("Phone                        : ").trim();
        string role = pickFrom("Role", ROLES, false) ?: "GUEST";
        profiles.push({user_id: userId, name: name, email: email, role: role, phone: phone});
    }
    if profiles.length() == 0 {
        io:println("Nothing to send.");
        return;
    }
    CreateUsersResponse response = check streamUsers(profiles);
    io:println(response.message);
    io:println("Created: ", response.created_user_ids.toString());
    foreach string failure in response.errors {
        io:println("  - ", failure);
    }
    return;
}

function addPropertyInteractive() returns error? {
    string hostId = readRequired("Host id (e.g. HOST-001) : ");
    string name = readRequired("Listing name            : ");
    string location = readRequired("Town                    : ");
    string region = readRequired("Region                  : ");
    string propertyType = pickFrom("Property type", PROPERTY_TYPES, false) ?: "APARTMENT";
    float price = readFloat("Price per night (N$)    : ", false);
    int guests = readInt("Sleeps (max guests)     : ", false);
    string description = io:readln("Description             : ").trim();

    AddPropertyResponse response = check rentalClient->add_property({
        host_id: hostId,
        name: name,
        location: location,
        region: region,
        property_type: propertyType,
        price_per_night: price,
        status: "AVAILABLE",
        max_guests: guests,
        description: description
    });
    io:println(response.success ? "OK  " : "!   ", response.message);
    if response.success {
        io:println("property_id = ", response.property_id);
    }
    return;
}

function updatePropertyInteractive() returns error? {
    string propertyId = readRequired("Property id (e.g. PROP-001) : ");
    SearchPropertyResponse current = check rentalClient->search_property({property_id: propertyId});
    Property? existing = current?.property;
    if existing is () {
        io:println(current.message);
        return;
    }
    printProperty(existing);
    io:println();

    string hostId = readRequired("Your host id                : ");
    io:println("Leave a field blank to keep its current value.");
    string name = io:readln("New name                    : ").trim();
    string location = io:readln("New town                    : ").trim();
    string region = io:readln("New region                  : ").trim();
    string propertyType = pickFrom("New property type", PROPERTY_TYPES, true) ?: "";
    float price = readFloat("New price per night (N$)    : ", true);
    int guests = readInt("New sleeps                  : ", true);
    string status = pickFrom("New status", PROPERTY_STATUSES, true) ?: "";
    string description = io:readln("New description             : ").trim();

    UpdatePropertyResponse response = check rentalClient->update_property({
        property_id: propertyId,
        host_id: hostId,
        name: name,
        location: location,
        region: region,
        property_type: propertyType,
        price_per_night: price,
        status: status,
        max_guests: guests,
        description: description
    });
    io:println(response.success ? "OK  " : "!   ", response.message);
    Property? property = response?.property;
    if property is Property {
        printProperty(property);
    }
    return;
}

function removePropertyInteractive() returns error? {
    string propertyId = readRequired("Property id : ");
    string hostId = readRequired("Host id     : ");
    RemovePropertyResponse response = check rentalClient->remove_property({
        property_id: propertyId,
        host_id: hostId
    });
    io:println(response.success ? "OK  " : "!   ", response.message);
    io:println("Remaining listings for this Host in that region: ",
            response.remaining_properties.length());
    foreach Property property in response.remaining_properties {
        io:println("  ", fit(property.property_id, 12), fit(property.name, 30), property.location);
    }
    return;
}

function listPropertiesInteractive() returns error? {
    io:println("Press Enter to skip any filter.");
    string location = io:readln("Town                 : ").trim();
    string region = io:readln("Region               : ").trim();
    float minPrice = readFloat("Minimum price (N$)   : ", true);
    float maxPrice = readFloat("Maximum price (N$)   : ", true);
    int guests = readInt("Number of guests     : ", true);
    string checkIn = readDate("Check-in (YYYY-MM-DD): ", true);
    string checkOut = checkIn == "" ? "" : readDate("Check-out (YYYY-MM-DD): ", false);
    io:println();

    int count = check streamProperties({
        location: location,
        region: region,
        min_price: minPrice,
        max_price: maxPrice,
        guests: guests,
        check_in: checkIn,
        check_out: checkOut
    });
    io:println(count, " listing(s) streamed back from the server.");
    return;
}

function searchPropertyInteractive() returns error? {
    string propertyId = readRequired("Property id : ");
    SearchPropertyResponse response = check rentalClient->search_property({property_id: propertyId});
    io:println(response.message);
    Property? property = response?.property;
    if property is Property {
        printProperty(property);
    }
    return;
}

function bookPropertyInteractive() returns error? {
    string guestId = readRequired("Guest id (e.g. GUEST-001)  : ");
    string propertyId = readRequired("Property id                : ");
    string checkIn = readDate("Check-in  (YYYY-MM-DD)     : ", false);
    string checkOut = readDate("Check-out (YYYY-MM-DD)     : ", false);
    int guests = readInt("Number of guests           : ", false);

    BookPropertyResponse response = check rentalClient->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests: guests
    });
    io:println(response.accepted ? "OK  " : "!   ", response.message);
    if response.accepted {
        io:println("cart item ", response.cart_item_id, ": ", response.nights,
                " nights, estimate N$", response.estimated_total);
    }
    return;
}

function confirmBookingInteractive() returns error? {
    string guestId = readRequired("Guest id                            : ");
    string cartItemId = io:readln("Cart item id (Enter for the whole cart): ").trim();
    ConfirmBookingResponse response = check rentalClient->confirm_booking({
        guest_id: guestId,
        cart_item_id: cartItemId
    });
    io:println(response.message);
    printBookings(response.bookings);
    foreach string rejection in response.rejected {
        io:println("  ! ", rejection);
    }
    if response.bookings.length() > 0 {
        io:println("  grand total = N$", response.grand_total);
    }
    return;
}

// ---------------------------------- input ----------------------------------

function readRequired(string label) returns string {
    while true {
        string value = io:readln(label).trim();
        if value != "" {
            return value;
        }
        io:println("   This field is required.");
    }
}

# Reads a whole number. When `optional`, a blank answer returns 0, which the
# contract treats as "not set".
function readInt(string label, boolean optional) returns int {
    while true {
        string value = io:readln(label).trim();
        if value == "" && optional {
            return 0;
        }
        int|error number = int:fromString(value);
        if number is int && number > 0 {
            return number;
        }
        io:println("   Please enter a whole number greater than zero.");
    }
}

# Reads an amount of money. When `optional`, a blank answer returns 0.0.
function readFloat(string label, boolean optional) returns float {
    while true {
        string value = io:readln(label).trim();
        if value == "" && optional {
            return 0.0;
        }
        float|error number = float:fromString(value);
        if number is float && number > 0.0 {
            return number;
        }
        io:println("   Please enter an amount greater than zero, e.g. 850 or 1195.50.");
    }
}

# Reads a calendar date in YYYY-MM-DD form. When `optional`, a blank answer
# returns an empty string.
function readDate(string label, boolean optional) returns string {
    while true {
        string value = io:readln(label).trim();
        if value == "" && optional {
            return "";
        }
        if value.length() == 10 && time:utcFromString(value + "T00:00:00Z") is time:Utc {
            return value;
        }
        io:println("   Please enter a real date in the form YYYY-MM-DD, e.g. 2026-12-18.");
    }
}

# Prints a numbered list and keeps asking until a valid number is entered.
# Returns `()` for a blank answer when `optional`.
function pickFrom(string title, string[] options, boolean optional) returns string? {
    io:println(title, ":");
    foreach int i in 0 ..< options.length() {
        io:println("   ", i + 1, ". ", options[i]);
    }
    string hint = optional ? " (Enter to keep current)" : "";
    while true {
        string answer = io:readln("   Choose 1-" + options.length().toString() + hint + ": ").trim();
        if answer == "" && optional {
            return ();
        }
        int|error number = int:fromString(answer);
        if number is int && number >= 1 && number <= options.length() {
            return options[number - 1];
        }
        io:println("   Please enter a number between 1 and ", options.length(), ".");
    }
}

function pause() {
    _ = io:readln("\nPress Enter to return to the menu...");
}

# Turns a gRPC failure into a message a user can act on.
function describe(error e) returns string {
    string message = e.message();
    if message.toLowerAscii().includes("connection refused") || message.toLowerAscii().includes("connect") {
        return "Cannot reach the gRPC server at " + serverUrl
                + " - start it first:  cd question2-rental-server && bal run  (" + message + ")";
    }
    return message;
}

// --------------------------------- rendering --------------------------------

function printBookings(Booking[] bookings) {
    foreach Booking booking in bookings {
        io:println("    ", booking.booking_id, "  ", booking.property_name, "  ",
                booking.check_in, " -> ", booking.check_out, "  ", booking.nights,
                " nights x N$", booking.price_per_night, " = N$", booking.total_cost);
    }
}

function printProperty(Property property) {
    io:println("  id          : ", property.property_id);
    io:println("  name        : ", property.name);
    io:println("  host        : ", property.host_id);
    io:println("  location    : ", property.location, ", ", property.region);
    io:println("  type        : ", property.property_type, ", sleeps ", property.max_guests);
    io:println("  price/night : N$", property.price_per_night);
    io:println("  status      : ", property.status);
    io:println("  description : ", property.description);
}

function fit(string value, int width) returns string {
    string text = value;
    if text.length() >= width {
        return text.substring(0, width - 1) + " ";
    }
    int index = text.length();
    while index < width {
        text += " ";
        index += 1;
    }
    return text;
}
