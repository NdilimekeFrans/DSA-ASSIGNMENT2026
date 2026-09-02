import ballerina/grpc;
import ballerina/log;

// ---------------------------------------------------------------------------
// Ministry of Tourism - Rental Accommodation System (gRPC server).
//
// The service implements the contract in `proto/rental.proto`:
//   simple RPCs        add_property, update_property, remove_property,
//                      search_property, book_property, confirm_booking
//   client streaming   create_users
//   server streaming   list_available_properties
//
// State lives in the isolated maps of `store.bal`, so the handlers below stay
// readable and the locking discipline stays in one file.
//
// If your Ballerina distribution generates a different descriptor annotation
// for the service (older versions emit `@grpc:ServiceDescriptor`), copy the
// annotation line from the file `bal grpc` generates and paste it here; the
// handler bodies are unaffected.
// ---------------------------------------------------------------------------

configurable int grpcPort = 9090;

listener grpc:Listener rentalListener = new (grpcPort);

function init() returns error? {
    check seed();
    log:printInfo("Rental accommodation service listening", port = grpcPort,
            properties = allProperties().length(), users = countUsers());
    return ();
}

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on rentalListener {

    // ---------------------------- add_property -----------------------------

    # Registers a new listing for a Host and allocates its unique id.
    remote function add_property(AddPropertyRequest request) returns AddPropertyResponse|error {
        if request.host_id.trim() == "" {
            return {success: false, property_id: "", message: "host_id is required"};
        }
        User? host = getUser(request.host_id);
        if host is () {
            return {
                success: false,
                property_id: "",
                message: "no registered user with id '" + request.host_id
                        + "'; create the Host profile first"
            };
        }
        if host.role != "HOST" {
            return {
                success: false,
                property_id: "",
                message: "user '" + request.host_id + "' is a " + host.role
                        + " and may not register properties"
            };
        }
        if request.name.trim() == "" {
            return {success: false, property_id: "", message: "the listing needs a name"};
        }
        if request.price_per_night <= 0.0 {
            return {success: false, property_id: "", message: "price_per_night must be greater than zero"};
        }

        string status = request.status.trim() == "" ? STATUS_AVAILABLE
            : request.status.trim().toUpperAscii();
        if status != STATUS_AVAILABLE && status != STATUS_UNAVAILABLE {
            return {
                success: false,
                property_id: "",
                message: "status must be AVAILABLE or UNAVAILABLE"
            };
        }

        string propertyId = nextId("PROP");
        Property property = {
            property_id: propertyId,
            host_id: request.host_id,
            name: request.name,
            location: request.location,
            region: request.region,
            property_type: request.property_type == "" ? "APARTMENT"
                : request.property_type.toUpperAscii(),
            price_per_night: request.price_per_night,
            status: status,
            max_guests: request.max_guests <= 0 ? 2 : request.max_guests,
            description: request.description
        };
        Property saved = saveProperty(property);
        log:printInfo("Property registered", property_id = saved.property_id, host = saved.host_id);
        return {
            success: true,
            property_id: saved.property_id,
            message: "'" + saved.name + "' registered in " + saved.location
        };
    }

    // ---------------------------- create_users -----------------------------

    # Client-side streaming. Profiles arrive one by one; a single summary is
    # returned once the client completes the stream. A rejected profile does
    # not abort the batch, it is reported back in `errors`.
    remote function create_users(stream<User, grpc:Error?> clientStream)
            returns CreateUsersResponse|error {
        string[] createdIds = [];
        string[] failures = [];

        while true {
            record {|User value;|}|grpc:Error? next = clientStream.next();
            if next is () {
                break;
            }
            if next is grpc:Error {
                log:printError("The user stream failed part way through", next);
                return {
                    success: false,
                    created_count: createdIds.length(),
                    rejected_count: failures.length(),
                    created_user_ids: createdIds,
                    errors: failures,
                    message: "the client stream failed: " + next.message()
                };
            }
            User user = next.value;
            string|error saved = saveUser(user);
            if saved is error {
                failures.push(user.name + ": " + saved.message());
            } else {
                createdIds.push(saved);
            }
        }

        log:printInfo("User batch processed", created = createdIds.length(),
                rejected = failures.length());
        return {
            success: failures.length() == 0,
            created_count: createdIds.length(),
            rejected_count: failures.length(),
            created_user_ids: createdIds,
            errors: failures,
            message: createdIds.length().toString() + " profile(s) registered, "
                    + failures.length().toString() + " rejected"
        };
    }

    // --------------------------- update_property ---------------------------

    # Updates a listing. Empty strings and zero values leave a field unchanged,
    # so the same call serves a price change and a full edit.
    remote function update_property(UpdatePropertyRequest request)
            returns UpdatePropertyResponse|error {
        Property? existing = getProperty(request.property_id);
        if existing is () {
            return {
                success: false,
                message: "no property with id '" + request.property_id + "'"
            };
        }
        if request.host_id.trim() != "" && existing.host_id != request.host_id {
            return {
                success: false,
                message: "property '" + request.property_id + "' belongs to another Host"
            };
        }

        Property updated = existing;
        if request.name.trim() != "" {
            updated.name = request.name;
        }
        if request.location.trim() != "" {
            updated.location = request.location;
        }
        if request.region.trim() != "" {
            updated.region = request.region;
        }
        if request.property_type.trim() != "" {
            updated.property_type = request.property_type.toUpperAscii();
        }
        if request.description.trim() != "" {
            updated.description = request.description;
        }
        if request.max_guests > 0 {
            updated.max_guests = request.max_guests;
        }
        if request.price_per_night > 0.0 {
            updated.price_per_night = request.price_per_night;
        }
        if request.status.trim() != "" {
            string status = request.status.trim().toUpperAscii();
            if status != STATUS_AVAILABLE && status != STATUS_UNAVAILABLE {
                return {success: false, message: "status must be AVAILABLE or UNAVAILABLE"};
            }
            updated.status = status;
        }

        Property saved = saveProperty(updated);
        return {
            success: true,
            message: "'" + saved.name + "' updated",
            property: saved
        };
    }

    // --------------------------- remove_property ---------------------------

    # Deletes a listing and replies with what the Host still has in that
    # region, as the contract requires.
    remote function remove_property(RemovePropertyRequest request)
            returns RemovePropertyResponse|error {
        Property? existing = getProperty(request.property_id);
        if existing is () {
            return {
                success: false,
                message: "no property with id '" + request.property_id + "'",
                remaining_properties: []
            };
        }
        if request.host_id.trim() != "" && existing.host_id != request.host_id {
            return {
                success: false,
                message: "property '" + request.property_id + "' belongs to another Host",
                remaining_properties: []
            };
        }
        Booking[] confirmed = bookingsForProperty(request.property_id);
        string todayDate = today();
        foreach Booking booking in confirmed {
            int|error remaining = nightsBetween(todayDate, booking.check_out);
            if remaining is int && remaining > 0 {
                return {
                    success: false,
                    message: "the listing has a confirmed stay running to " + booking.check_out
                            + " and cannot be removed yet",
                    remaining_properties: propertiesInRegion(existing.host_id, existing.region)
                };
            }
        }

        Property? removed = deleteProperty(request.property_id);
        string name = removed is Property ? removed.name : request.property_id;
        log:printInfo("Property removed", property_id = request.property_id);
        return {
            success: true,
            message: "'" + name + "' removed from the listings",
            remaining_properties: propertiesInRegion(existing.host_id, existing.region)
        };
    }

    // ---------------------- list_available_properties ----------------------

    # Server-side streaming. Matching listings are streamed back one at a time
    # rather than as one large response.
    remote function list_available_properties(ListPropertiesRequest request)
            returns stream<Property, error?>|error {
        Property[] matches = [];
        foreach Property property in allProperties() {
            if property.status != STATUS_AVAILABLE {
                continue;
            }
            if request.location.trim() != ""
                    && !equalsIgnoreCase(property.location, request.location.trim()) {
                continue;
            }
            if request.region.trim() != ""
                    && !equalsIgnoreCase(property.region, request.region.trim()) {
                continue;
            }
            if request.min_price > 0.0 && property.price_per_night < request.min_price {
                continue;
            }
            if request.max_price > 0.0 && property.price_per_night > request.max_price {
                continue;
            }
            if request.guests > 0 && property.max_guests < request.guests {
                continue;
            }
            if request.check_in.trim() != "" && request.check_out.trim() != "" {
                boolean|error clash = hasDateClash(property.property_id, request.check_in,
                        request.check_out);
                if clash is error {
                    return error grpc:AbortedError("check_in and check_out must be calendar "
                            + "dates in YYYY-MM-DD form");
                }
                if clash {
                    continue;
                }
            }
            matches.push(property);
        }
        log:printInfo("Streaming property list", matches = matches.length());
        return matches.toStream();
    }

    // ---------------------------- search_property --------------------------

    # Looks up a single listing. An unknown or unavailable listing produces a
    # "Not Available" answer rather than an error, as the contract requires.
    remote function search_property(SearchPropertyRequest request)
            returns SearchPropertyResponse|error {
        Property? found = getProperty(request.property_id);
        if found is () {
            return {
                available: false,
                message: "Not Available - no listing with id '" + request.property_id + "'"
            };
        }
        if found.status != STATUS_AVAILABLE {
            return {
                available: false,
                message: "Not Available - '" + found.name + "' is currently " + found.status,
                property: found
            };
        }
        return {
            available: true,
            message: "'" + found.name + "' is available at N$"
                    + found.price_per_night.toString() + " per night",
            property: found
        };
    }

    // ----------------------------- book_property ---------------------------

    # Validates a requested stay and places it in the Guest's temporary cart.
    # Nothing is committed here; `confirm_booking` does that.
    remote function book_property(BookPropertyRequest request) returns BookPropertyResponse|error {
        User? guest = getUser(request.guest_id);
        if guest is () {
            return {
                accepted: false,
                message: "no registered user with id '" + request.guest_id + "'",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        if guest.role != "GUEST" {
            return {
                accepted: false,
                message: "user '" + request.guest_id + "' is a Host, not a Guest",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        Property? property = getProperty(request.property_id);
        if property is () {
            return {
                accepted: false,
                message: "no listing with id '" + request.property_id + "'",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        if property.status != STATUS_AVAILABLE {
            return {
                accepted: false,
                message: "'" + property.name + "' is currently " + property.status,
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        if !isValidDate(request.check_in) || !isValidDate(request.check_out) {
            return {
                accepted: false,
                message: "check_in and check_out must be calendar dates in YYYY-MM-DD form",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        int nights = check nightsBetween(request.check_in, request.check_out);
        if nights <= 0 {
            return {
                accepted: false,
                message: "the check-out date must be after the check-in date",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        if request.guests > 0 && request.guests > property.max_guests {
            return {
                accepted: false,
                message: "'" + property.name + "' sleeps " + property.max_guests.toString()
                        + " guests, " + request.guests.toString() + " requested",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        boolean clash = check hasDateClash(request.property_id, request.check_in, request.check_out);
        if clash {
            return {
                accepted: false,
                message: "'" + property.name + "' is already booked over part of those dates",
                cart_item_id: "",
                nights: nights,
                estimated_total: 0.0
            };
        }

        float estimate = round2(property.price_per_night * <float>nights);
        string cartItemId = nextId("CART");
        addToCart({
            cartItemId: cartItemId,
            guestId: request.guest_id,
            propertyId: request.property_id,
            checkIn: request.check_in,
            checkOut: request.check_out,
            guests: request.guests,
            nights: nights,
            estimatedTotal: estimate
        });
        return {
            accepted: true,
            message: "added to your booking cart; call confirm_booking to finalise",
            cart_item_id: cartItemId,
            nights: nights,
            estimated_total: estimate
        };
    }

    // ---------------------------- confirm_booking --------------------------

    # Finalises the cart: re-checks availability for the requested dates,
    # calculates the total cost and clears the confirmed items.
    remote function confirm_booking(ConfirmBookingRequest request)
            returns ConfirmBookingResponse|error {
        CartItem[] cart = cartFor(request.guest_id);
        if cart.length() == 0 {
            return {
                confirmed: false,
                message: "there is nothing in the booking cart for '" + request.guest_id + "'",
                bookings: [],
                grand_total: 0.0,
                rejected: []
            };
        }

        CartItem[] selected = cart;
        if request.cart_item_id.trim() != "" {
            selected = from CartItem item in cart
                where item.cartItemId == request.cart_item_id.trim()
                select item;
            if selected.length() == 0 {
                return {
                    confirmed: false,
                    message: "cart item '" + request.cart_item_id + "' is not in this Guest's cart",
                    bookings: [],
                    grand_total: 0.0,
                    rejected: []
                };
            }
        }

        Booking[] confirmedBookings = [];
        string[] rejected = [];
        string[] confirmedCartIds = [];
        float grandTotal = 0.0;

        foreach CartItem item in selected {
            Property? property = getProperty(item.propertyId);
            if property is () {
                rejected.push(item.cartItemId + ": the listing has since been removed");
                continue;
            }
            if property.status != STATUS_AVAILABLE {
                rejected.push(item.cartItemId + ": '" + property.name + "' is now "
                        + property.status);
                continue;
            }
            boolean clash = check hasDateClash(item.propertyId, item.checkIn, item.checkOut);
            if clash {
                rejected.push(item.cartItemId + ": '" + property.name
                        + "' was booked by someone else for those dates");
                continue;
            }

            int nights = check nightsBetween(item.checkIn, item.checkOut);
            float total = round2(property.price_per_night * <float>nights);
            Booking booking = {
                booking_id: nextId("BKG"),
                property_id: property.property_id,
                property_name: property.name,
                guest_id: item.guestId,
                check_in: item.checkIn,
                check_out: item.checkOut,
                nights: nights,
                price_per_night: property.price_per_night,
                total_cost: total,
                status: BOOKING_CONFIRMED
            };
            saveBooking(booking);
            confirmedBookings.push(booking);
            confirmedCartIds.push(item.cartItemId);
            grandTotal += total;
        }

        clearCartItems(request.guest_id, confirmedCartIds);
        log:printInfo("Booking cart processed", guest = request.guest_id,
                confirmed = confirmedBookings.length(), rejected = rejected.length());

        return {
            confirmed: confirmedBookings.length() > 0,
            message: confirmedBookings.length().toString() + " booking(s) confirmed"
                    + (rejected.length() > 0 ? ", " + rejected.length().toString() + " rejected" : ""),
            bookings: confirmedBookings,
            grand_total: round2(grandTotal),
            rejected: rejected
        };
    }
}
