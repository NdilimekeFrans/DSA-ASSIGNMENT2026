import ballerina/io;

// ---------------------------------------------------------------------------
// Ministry of Tourism - Rental Accommodation System (gRPC client).
//
// The client exercises every operation in the contract, including the two
// streaming ones:
//   create_users               client-side streaming
//   list_available_properties  server-side streaming
//
// Option 1 runs the whole story end to end, which is the quickest way to see
// the system work; the remaining options drive each RPC on its own.
// ---------------------------------------------------------------------------

configurable string serverUrl = "http://localhost:9090";

final RentalServiceClient rentalClient = check new (serverUrl);

public function main() returns error? {
    io:println();
    io:println("=========================================================");
    io:println(" Ministry of Tourism - Rental Accommodation System");
    io:println(" gRPC client connected to ", serverUrl);
    io:println("=========================================================");

    while true {
        printMenu();
        string choice = io:readln("Select an option: ").trim();
        io:println();
        if choice == "0" {
            io:println("Goodbye.");
            return;
        }
        error? outcome = dispatch(choice);
        if outcome is error {
            io:println("  ! ", outcome.message());
        }
        io:println();
    }
}

function printMenu() {
    io:println("---------------------------------------------------------");
    io:println(" 1. Run the full demonstration (all eight operations)");
    io:println(" 2. create_users            (client streaming)");
    io:println(" 3. add_property            (simple)");
    io:println(" 4. update_property         (simple)");
    io:println(" 5. remove_property         (simple)");
    io:println(" 6. list_available_properties (server streaming)");
    io:println(" 7. search_property         (simple)");
    io:println(" 8. book_property           (simple)");
    io:println(" 9. confirm_booking         (simple)");
    io:println(" 0. Exit");
    io:println("---------------------------------------------------------");
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
    io:println("Unknown option '", choice, "'.");
    return;
}

// ---------------------------- guided demonstration --------------------------

function runDemonstration() returns error? {
    string hostId = "HOST-" + timestampSuffix();
    string guestId = "GUEST-" + timestampSuffix();

    banner("1. create_users - streaming three profiles to the server");
    User[] profiles = [
        {user_id: hostId, name: "Johanna Amutenya", email: "johanna@namib-stays.na", role: "HOST", phone: "+264 81 700 1000"},
        {user_id: guestId, name: "Thomas Kambwale", email: "thomas@example.na", role: "GUEST", phone: "+264 81 700 2000"},
        {user_id: "", name: "Nobody", email: "nobody@example.na", role: "TOURIST", phone: ""}
    ];
    CreateUsersResponse batch = check streamUsers(profiles);
    io:println("  created  : ", batch.created_count, " -> ", batch.created_user_ids.toString());
    io:println("  rejected : ", batch.rejected_count);
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
    foreach Booking booking in confirmed.bookings {
        io:println("    ", booking.booking_id, "  ", booking.property_name, "  ",
                booking.check_in, " -> ", booking.check_out, "  ", booking.nights,
                " nights x N$", booking.price_per_night, " = N$", booking.total_cost);
    }
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
    return;
}

function banner(string title) {
    io:println();
    io:println("--- ", title, " ---");
}

function timestampSuffix() returns string {
    return nextSequence().toString();
}

int counter = 100;

function nextSequence() returns int {
    counter += 1;
    return counter;
}

// ------------------------------ streaming helpers --------------------------

# Client-side streaming: open the stream, send every profile, complete it, then
# read the single summary the server sends back.
function streamUsers(User[] profiles) returns CreateUsersResponse|error {
    var streamingClient = check rentalClient->create_users();
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
# each listing as it arrives.
function streamProperties(ListPropertiesRequest request) returns int|error {
    var properties = check rentalClient->list_available_properties(request);
    int count = 0;
    io:println("  ", fit("ID", 12), fit("NAME", 30), fit("LOCATION", 16), fit("REGION", 16),
            fit("TYPE", 12), fit("SLEEPS", 8), "PRICE/NIGHT");
    while true {
        record {|Property value;|}|error? next = properties.next();
        if next is () {
            break;
        }
        if next is error {
            return next;
        }
        Property property = next.value;
        count += 1;
        io:println("  ", fit(property.property_id, 12), fit(property.name, 30),
                fit(property.location, 16), fit(property.region, 16),
                fit(property.property_type, 12), fit(property.max_guests.toString(), 8),
                "N$", property.price_per_night);
    }
    check properties.close();
    return count;
}

// ----------------------------- interactive options -------------------------

function createUsersInteractive() returns error? {
    User[] profiles = [];
    io:println("Enter user profiles. Leave the name blank to finish.");
    while true {
        string name = io:readln("Name  : ").trim();
        if name == "" {
            break;
        }
        profiles.push({
            user_id: io:readln("Id (blank to auto-generate): ").trim(),
            name: name,
            email: io:readln("Email : ").trim(),
            role: io:readln("Role (HOST/GUEST): ").trim().toUpperAscii(),
            phone: io:readln("Phone : ").trim()
        });
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
    string price = io:readln("Price per night : ").trim();
    string guests = io:readln("Sleeps          : ").trim();
    AddPropertyResponse response = check rentalClient->add_property({
        host_id: io:readln("Host id         : ").trim(),
        name: io:readln("Listing name    : ").trim(),
        location: io:readln("Town            : ").trim(),
        region: io:readln("Region          : ").trim(),
        property_type: io:readln("Type            : ").trim().toUpperAscii(),
        price_per_night: check float:fromString(price == "" ? "0" : price),
        status: "AVAILABLE",
        max_guests: check int:fromString(guests == "" ? "0" : guests),
        description: io:readln("Description     : ").trim()
    });
    io:println(response.success ? "OK  " : "!   ", response.message);
    if response.success {
        io:println("property_id = ", response.property_id);
    }
    return;
}

function updatePropertyInteractive() returns error? {
    io:println("Leave a field blank (or zero) to keep its current value.");
    string price = io:readln("New price per night : ").trim();
    string guests = io:readln("New sleeps          : ").trim();
    UpdatePropertyResponse response = check rentalClient->update_property({
        property_id: io:readln("Property id         : ").trim(),
        host_id: io:readln("Host id             : ").trim(),
        name: io:readln("New name            : ").trim(),
        location: io:readln("New town            : ").trim(),
        region: io:readln("New region          : ").trim(),
        property_type: io:readln("New type            : ").trim().toUpperAscii(),
        price_per_night: check float:fromString(price == "" ? "0" : price),
        status: io:readln("New status          : ").trim().toUpperAscii(),
        max_guests: check int:fromString(guests == "" ? "0" : guests),
        description: io:readln("New description     : ").trim()
    });
    io:println(response.success ? "OK  " : "!   ", response.message);
    Property? property = response?.property;
    if property is Property {
        printProperty(property);
    }
    return;
}

function removePropertyInteractive() returns error? {
    RemovePropertyResponse response = check rentalClient->remove_property({
        property_id: io:readln("Property id : ").trim(),
        host_id: io:readln("Host id     : ").trim()
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
    string minPrice = io:readln("Minimum price (blank for none) : ").trim();
    string maxPrice = io:readln("Maximum price (blank for none) : ").trim();
    string guests = io:readln("Guests        (blank for any)  : ").trim();
    int count = check streamProperties({
        location: io:readln("Town          (blank for any)  : ").trim(),
        region: io:readln("Region        (blank for any)  : ").trim(),
        min_price: check float:fromString(minPrice == "" ? "0" : minPrice),
        max_price: check float:fromString(maxPrice == "" ? "0" : maxPrice),
        guests: check int:fromString(guests == "" ? "0" : guests),
        check_in: io:readln("Check-in      (blank for any)  : ").trim(),
        check_out: io:readln("Check-out     (blank for any)  : ").trim()
    });
    io:println(count, " listing(s) streamed back from the server.");
    return;
}

function searchPropertyInteractive() returns error? {
    SearchPropertyResponse response = check rentalClient->search_property({
        property_id: io:readln("Property id : ").trim()
    });
    io:println(response.message);
    Property? property = response?.property;
    if property is Property {
        printProperty(property);
    }
    return;
}

function bookPropertyInteractive() returns error? {
    string guests = io:readln("Number of guests : ").trim();
    BookPropertyResponse response = check rentalClient->book_property({
        guest_id: io:readln("Guest id         : ").trim(),
        property_id: io:readln("Property id      : ").trim(),
        check_in: io:readln("Check-in         : ").trim(),
        check_out: io:readln("Check-out        : ").trim(),
        guests: check int:fromString(guests == "" ? "0" : guests)
    });
    io:println(response.accepted ? "OK  " : "!   ", response.message);
    if response.accepted {
        io:println("cart item ", response.cart_item_id, ": ", response.nights,
                " nights, estimate N$", response.estimated_total);
    }
    return;
}

function confirmBookingInteractive() returns error? {
    ConfirmBookingResponse response = check rentalClient->confirm_booking({
        guest_id: io:readln("Guest id                              : ").trim(),
        cart_item_id: io:readln("Cart item id (blank for everything)   : ").trim()
    });
    io:println(response.message);
    foreach Booking booking in response.bookings {
        io:println("  ", booking.booking_id, "  ", booking.property_name, "  ",
                booking.check_in, " -> ", booking.check_out, "  ", booking.nights,
                " nights x N$", booking.price_per_night, " = N$", booking.total_cost);
    }
    foreach string rejection in response.rejected {
        io:println("  ! ", rejection);
    }
    if response.bookings.length() > 0 {
        io:println("  grand total = N$", response.grand_total);
    }
    return;
}

// --------------------------------- rendering --------------------------------

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
