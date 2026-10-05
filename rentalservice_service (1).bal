import ballerina/grpc;

listener grpc:Listener ep = new (9090);

isolated class RentalStore {

    private map<Property & readonly> properties = {};
    private map<User & readonly> users = {};
    private map<BookingRequest & readonly> bookings = {};

    isolated function addProperty(Property value) {
        lock {
            self.properties[value.property_id] = value.cloneReadOnly();
        }
    }

    isolated function updateProperty(Property value) returns boolean {
        lock {
            if self.properties.hasKey(value.property_id) {
                self.properties[value.property_id] = value.cloneReadOnly();
                return true;
            }

            return false;
        }
    }

    isolated function removeProperty(string propertyId) returns Property[] {
        lock {
            if self.properties.hasKey(propertyId) {
                _ = self.properties.remove(propertyId);
            }

            return self.properties.toArray().clone();
        }
    }

    isolated function findProperty(string propertyId) returns Property? {
        lock {
            if self.properties.hasKey(propertyId) {
                return self.properties.get(propertyId).clone();
            }

            return ();
        }
    }

    isolated function addBooking(BookingRequest value) {
        string bookingKey = value.guest_id + ":" + value.property_id;

        lock {
            self.bookings[bookingKey] = value.cloneReadOnly();
        }
    }

    isolated function getBooking(string bookingKey) returns BookingRequest? {
        lock {
            if self.bookings.hasKey(bookingKey) {
                return self.bookings.get(bookingKey).clone();
            }

            return ();
        }
    }

    isolated function addUser(User user) {
        lock {
            self.users[user.user_id] = user.cloneReadOnly();
        }
    }

    isolated function getUserCount() returns int {
        lock {
            return self.users.length();
        }
    }

    isolated function getAvailableProperties(PropertyFilter value)
            returns Property[] {

        lock {
            Property[] result = [];

            foreach Property property in self.properties {
                if property.available &&
                    property.location == value.location &&
                    property.price_per_night <= value.max_price {

                    result.push(property.clone());
                }
            }

            return result.clone();
        }
    }
}

final RentalStore store = new;

isolated function dateToDays(string date) returns int|error {
    string[] parts = re `-`.split(date);

    if parts.length() != 3 {
        return error("Invalid date format. Use YYYY-MM-DD.");
    }

    int year = check int:fromString(parts[0]);
    int month = check int:fromString(parts[1]);
    int day = check int:fromString(parts[2]);

    if month < 1 || month > 12 || day < 1 || day > 31 {
        return error("Invalid date.");
    }

    int[] daysInMonth = [
        31, 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31
    ];

    boolean leapYear = (year % 4 == 0 && year % 100 != 0) ||
        year % 400 == 0;

    if leapYear {
        daysInMonth[1] = 29;
    }

    if day > daysInMonth[month - 1] {
        return error("Invalid date.");
    }

    int totalDays = 0;
    int previousYear = year - 1;

    totalDays += previousYear * 365;
    totalDays += previousYear / 4;
    totalDays -= previousYear / 100;
    totalDays += previousYear / 400;

    foreach int i in 0 ..< month - 1 {
        totalDays += daysInMonth[i];
    }

    totalDays += day;

    return totalDays;
}

isolated function addUserToStore(User user) {
    store.addUser(user);
}

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on ep {

    remote function add_property(Property value)
            returns PropertyResponse|error {

        store.addProperty(value);

        return {
            message: "Property added successfully",
            property: value
        };
    }

    remote function update_property(Property value)
            returns PropertyResponse|error {

        boolean updated = store.updateProperty(value);

        if updated {
            return {
                message: "Property updated successfully",
                property: value
            };
        }

        return {
            message: "Property not found"
        };
    }

    remote function remove_property(PropertyRequest value)
            returns PropertyList|error {

        Property[] remaining = store.removeProperty(value.property_id);

        return {
            properties: remaining
        };
    }

    remote function search_property(PropertyRequest value)
            returns PropertyResponse|error {

        Property? result = store.findProperty(value.property_id);

        if result is Property {
            return {
                message: "Property found",
                property: result
            };
        }

        return {
            message: "Property not found"
        };
    }

    remote function book_property(BookingRequest value)
            returns BookingResponse|error {

        store.addBooking(value);

        return {
            message: "Booking created successfully",
            property_id: value.property_id
        };
    }

    remote function confirm_booking(ConfirmBookingRequest value)
            returns BookingConfirmation|error {

        string bookingKey = value.guest_id + ":" + value.property_id;

        BookingRequest? bookingResult = store.getBooking(bookingKey);

        if bookingResult is () {
            return error("Booking not found.");
        }

        Property? propertyResult = store.findProperty(value.property_id);

        if propertyResult is () {
            return error("Property not found.");
        }

        BookingRequest booking = bookingResult;
        Property property = propertyResult;

        int checkInDays = check dateToDays(booking.check_in);
        int checkOutDays = check dateToDays(booking.check_out);

        int nights = checkOutDays - checkInDays;

        if nights <= 0 {
            return error("Check-out date must be after check-in date.");
        }

        float totalPrice = <float>nights * property.price_per_night;

        return {
            message: "Booking confirmed",
            total_price: totalPrice,
            nights: nights
        };
    }

    remote function create_users(stream<User, grpc:Error?> clientStream)
            returns UserResponse|error {

        error? streamError = clientStream.forEach(function(User user) {
            addUserToStore(user);
        });

        if streamError is error {
            return streamError;
        }

        int count = store.getUserCount();

        return {
            message: "Users created successfully",
            users_created: count
        };
    }

    remote function list_available_properties(PropertyFilter value)
            returns stream<Property, error?>|error {

        Property[] availableProperties =
            store.getAvailableProperties(value);

        return availableProperties.toStream();
    }
}