import ballerina/grpc;
import ballerina/io;

public function main() returns error? {
    RentalServiceClient rentalClient = check new ("http://localhost:9090");

    io:println("=== 1. ADD PROPERTY ===");
    Property property = {
        property_id: "P004",
        host_id: "H004",
        name: "Palm Gardens",
        location: "Ongwediva",
        price_per_night: 650.0,
        description: "A peaceful guest apartment",
        available: true
    };
    PropertyResponse addResponse = check rentalClient->add_property(property);
    io:println(addResponse.message);

    io:println("\n=== 2. SEARCH PROPERTY ===");
    PropertyRequest searchReq = {property_id: "P004"};
    PropertyResponse searchResp = check rentalClient->search_property(searchReq);
    io:println(searchResp.message);

    io:println("\n=== 3. UPDATE PROPERTY ===");
    Property updatedProperty = {
        property_id: "P004",
        host_id: "H004",
        name: "Palm Gardens Luxury Suite",
        location: "Ongwediva",
        price_per_night: 650.0,
        description: "An upgraded peaceful guest apartment",
        available: true
    };
    PropertyResponse updateResp = check rentalClient->update_property(updatedProperty);
    io:println(updateResp.message);

    io:println("\n=== 4. LIST AVAILABLE PROPERTIES (Server Streaming) ===");
    PropertyFilter filter = {location: "Ongwediva", max_price: 1000.0};
    stream<Property, grpc:Error?> propStream = check rentalClient->list_available_properties(filter);
    check propStream.forEach(function(Property p) {
        io:println("Found property: ", p.name, " - N$", p.price_per_night);
    });

    io:println("\n=== 5. CREATE USERS (Client Streaming) ===");
    Create_usersStreamingClient userStreamingClient = check rentalClient->create_users();
    check userStreamingClient->sendUser({user_id: "U001", name: "Alice"});
    check userStreamingClient->sendUser({user_id: "U002", name: "Bob"});
    check userStreamingClient->complete();
    UserResponse? userResp = check userStreamingClient->receiveUserResponse();
    if userResp is UserResponse {
        io:println(userResp.message);
    }

    io:println("\n=== 6. BOOK PROPERTY ===");
    BookingRequest booking = {
        property_id: "P004",
        guest_id: "U001",
        check_in: "2026-09-15",
        check_out: "2026-09-18"
    };
    BookingResponse bookingResponse = check rentalClient->book_property(booking);
    io:println(bookingResponse.message);

    io:println("\n=== 7. CONFIRM BOOKING ===");
    ConfirmBookingRequest request = {
        guest_id: "U001",
        property_id: "P004"
    };
    BookingConfirmation response = check rentalClient->confirm_booking(request);
    io:println(response.message);
    io:println("Total price: N$", response.total_price);
    io:println("Nights: ", response.nights);

    io:println("\n=== 8. REMOVE PROPERTY ===");
    PropertyList remainingList = check rentalClient->remove_property({property_id: "P004"});
    io:println("Property removed. Remaining properties count: ", remainingList.properties.length());
}