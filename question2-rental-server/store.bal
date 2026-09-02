// ---------------------------------------------------------------------------
// In-memory data store for the rental accommodation service.
//
// Properties, users and confirmed bookings are held in `map`s keyed on their
// unique ids; each Guest's temporary "booking cart" is a map from guest id to
// the list of pending stays.
//
// The maps are `isolated` module-level variables and every read or write goes
// through a `lock`, so the server stays correct while gRPC serves requests
// concurrently. Values are cloned across the lock boundary so no caller can
// mutate stored state behind the store's back.
// ---------------------------------------------------------------------------

# A stay a Guest has put in the cart but has not yet confirmed.
public type CartItem record {|
    string cartItemId;
    string guestId;
    string propertyId;
    string checkIn;
    string checkOut;
    int guests;
    int nights;
    float estimatedTotal;
|};

public const string STATUS_AVAILABLE = "AVAILABLE";
public const string STATUS_UNAVAILABLE = "UNAVAILABLE";
public const string BOOKING_CONFIRMED = "CONFIRMED";

isolated map<Property> propertyStore = {};
isolated map<User> userStore = {};
isolated map<Booking> bookingStore = {};
isolated map<CartItem[]> cartStore = {};

// --------------------------------- users -----------------------------------

public isolated function saveUser(User user) returns string|error {
    if user.name.trim() == "" {
        return error("a user profile needs a name");
    }
    string role = user.role.trim().toUpperAscii();
    if role != "HOST" && role != "GUEST" {
        return error("role must be HOST or GUEST, found '" + user.role + "'");
    }
    string userId = user.user_id.trim() == "" ? nextId(role == "HOST" ? "HOST" : "GUEST")
        : user.user_id.trim();
    lock {
        if userStore.hasKey(userId) {
            return error("user '" + userId + "' already exists");
        }
        User candidate = user.clone();
        candidate.user_id = userId;
        candidate.role = role;
        userStore[userId] = candidate;
    }
    return userId;
}

public isolated function getUser(string userId) returns User? {
    lock {
        User? found = userStore[userId];
        return found is User ? found.clone() : ();
    }
}

public isolated function countUsers() returns int {
    lock {
        return userStore.length();
    }
}

// ------------------------------- properties --------------------------------

public isolated function saveProperty(Property property) returns Property {
    lock {
        Property stored = property.clone();
        propertyStore[stored.property_id] = stored;
        return stored.clone();
    }
}

public isolated function getProperty(string propertyId) returns Property? {
    lock {
        Property? found = propertyStore[propertyId];
        return found is Property ? found.clone() : ();
    }
}

public isolated function deleteProperty(string propertyId) returns Property? {
    lock {
        Property? removed = propertyStore.removeIfHasKey(propertyId);
        return removed is Property ? removed.clone() : ();
    }
}

public isolated function allProperties() returns Property[] {
    lock {
        return propertyStore.toArray().clone();
    }
}

# Every listing a Host still owns in a given region, used by `remove_property`.
public isolated function propertiesInRegion(string hostId, string region) returns Property[] {
    lock {
        Property[] results = from Property property in propertyStore
            where property.host_id == hostId && equalsIgnoreCase(property.region, region)
            select property;
        return results.clone();
    }
}

public isolated function equalsIgnoreCase(string a, string b) returns boolean {
    return a.toLowerAscii() == b.toLowerAscii();
}

// -------------------------------- bookings ---------------------------------

public isolated function saveBooking(Booking booking) {
    lock {
        bookingStore[booking.booking_id] = booking.clone();
    }
}

public isolated function bookingsForProperty(string propertyId) returns Booking[] {
    lock {
        Booking[] results = from Booking booking in bookingStore
            where booking.property_id == propertyId && booking.status == BOOKING_CONFIRMED
            select booking;
        return results.clone();
    }
}

# `true` when a confirmed booking already covers part of the requested stay.
public isolated function hasDateClash(string propertyId, string checkIn, string checkOut)
        returns boolean|error {
    foreach Booking booking in bookingsForProperty(propertyId) {
        boolean overlap = check staysOverlap(checkIn, checkOut, booking.check_in, booking.check_out);
        if overlap {
            return true;
        }
    }
    return false;
}

// ---------------------------------- cart -----------------------------------

public isolated function addToCart(CartItem item) {
    lock {
        CartItem[] items = cartStore[item.guestId] ?: [];
        items.push(item.clone());
        cartStore[item.guestId] = items.clone();
    }
}

public isolated function cartFor(string guestId) returns CartItem[] {
    lock {
        CartItem[] items = cartStore[guestId] ?: [];
        return items.clone();
    }
}

# Removes the confirmed items from the Guest's cart, keeping anything that was
# rejected so the Guest can correct and retry it.
public isolated function clearCartItems(string guestId, string[] confirmedIds) {
    lock {
        CartItem[] items = cartStore[guestId] ?: [];
        string[] ids = confirmedIds.clone();
        CartItem[] remaining = from CartItem item in items
            where ids.indexOf(item.cartItemId) is ()
            select item;
        cartStore[guestId] = remaining.clone();
    }
}

// --------------------------------- seeding ---------------------------------

# Loads a small demonstration data set so the client has something to list on
# a fresh start.
public isolated function seed() returns error? {
    User[] users = [
        {user_id: "HOST-001", name: "Selma Nakale", email: "selma@etosha-stays.na", role: "HOST", phone: "+264 81 111 2222"},
        {user_id: "HOST-002", name: "Petrus Haingura", email: "petrus@kavango-lodges.na", role: "HOST", phone: "+264 81 333 4444"},
        {user_id: "GUEST-001", name: "Maria Iipumbu", email: "maria@example.na", role: "GUEST", phone: "+264 85 555 6666"}
    ];
    foreach User user in users {
        string _ = check saveUser(user);
    }

    Property[] properties = [
        {
            property_id: "PROP-001",
            host_id: "HOST-001",
            name: "Dune Breeze Apartment",
            location: "Swakopmund",
            region: "Erongo",
            property_type: "APARTMENT",
            price_per_night: 850.0,
            status: STATUS_AVAILABLE,
            max_guests: 4,
            description: "Two-bedroom apartment one block from the beachfront."
        },
        {
            property_id: "PROP-002",
            host_id: "HOST-001",
            name: "Etosha Gate Guesthouse",
            location: "Outjo",
            region: "Kunene",
            property_type: "GUESTHOUSE",
            price_per_night: 1200.0,
            status: STATUS_AVAILABLE,
            max_guests: 6,
            description: "Family guesthouse forty minutes from the Anderson gate."
        },
        {
            property_id: "PROP-003",
            host_id: "HOST-002",
            name: "Okavango River Lodge",
            location: "Rundu",
            region: "Kavango East",
            property_type: "LODGE",
            price_per_night: 1650.0,
            status: STATUS_AVAILABLE,
            max_guests: 2,
            description: "Riverside chalet with a private deck over the Okavango."
        },
        {
            property_id: "PROP-004",
            host_id: "HOST-002",
            name: "Kavango Campsite Pitch 7",
            location: "Divundu",
            region: "Kavango East",
            property_type: "CAMPSITE",
            price_per_night: 320.0,
            status: STATUS_UNAVAILABLE,
            max_guests: 8,
            description: "Shaded pitch with power; closed for renovation."
        }
    ];
    foreach Property property in properties {
        Property _ = saveProperty(property);
    }
    return ();
}
