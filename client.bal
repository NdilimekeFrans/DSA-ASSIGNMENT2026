import ballerina/http;
import ballerina/io;

public function main() {


    io:println(" ....... CAMPUS LIBRARY Ballerina CLIENT");

 // CONNECT TO THE CAMPUS LIBRARY SERVER


    http:Client|error clientOrError =
        new ("http://localhost:8080");

    if clientOrError is error {
        io:println("\n[CLIENT ERROR]");
        io:println("Failed to create HTTP client: ",
            clientOrError.message());
        return;
    }

    http:Client apiClient = clientOrError;

    io:println("\n[CLIENT] Connected to Campus Library Server.");
    io:println("[CLIENT] Server address: http://localhost:8080");


    do {

        // 1. GET ALL ASSETS


        io:println("1. CLIENT -> GET /assets");
        io:println("   CLIENT: Calling server...");
        
        json allAssets = check apiClient->get("/assets");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET ALL ASSETS successful.");
        io:println(allAssets);


        // 2. GET ONE ASSET

        io:println("2. CLIENT -> GET /assets/DB-TEST-002");
        io:println("   CLIENT: Calling server...");

        json singleAsset =
            check apiClient->get("/assets/DB-TEST-002");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET ONE ASSET successful.");
        io:println(singleAsset);


        // 3. GET ASSETS BY INSTITUTION

        io:println("3. CLIENT -> GET /assets/institution/NUST");
        io:println("   CLIENT: Calling server...");

        json institutionAssets =
            check apiClient->get("/assets/institution/NUST");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET BY INSTITUTION successful.");
        io:println(institutionAssets);


        // 4. GET ASSETS BY SITE

        io:println("4. CLIENT -> GET /assets/site/Main%20Campus");
        io:println("   CLIENT: Calling server...");

        json siteAssets =
            check apiClient->get("/assets/site/Main%20Campus");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET BY SITE successful.");
        io:println(siteAssets);


        // 5. GET INSTITUTIONS


        io:println("5. CLIENT -> GET /assets/institutions");
        io:println("   CLIENT: Calling server...");

        json institutions =
            check apiClient->get("/assets/institutions");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET INSTITUTIONS successful.");
        io:println(institutions);


        // 6. GET OVERDUE MAINTENANCE

        io:println("6. CLIENT -> GET /assets/overdue");
        io:println("   CLIENT: Calling server...");

        json overdueAssets =
            check apiClient->get("/assets/overdue");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: GET OVERDUE MAINTENANCE successful.");
        io:println(overdueAssets);



        // 7. CREATE TEST ASSET

        io:println("7. CLIENT -> POST /assets");
        io:println("   CLIENT: Calling server to create asset...");

        json newAsset = {
            assetTag: "CLIENT-TEST-001",
            name: "Client Test Laptop",
            description: "Asset created through the Ballerina client",
            institution: "NUST",
            site: "Main Campus",
            status: "AVAILABLE",
            dateAcquired: "2026-10-06",
            components: [],
            schedules: [],
            workOrders: []
        };

        http:Response createResponse =
            check apiClient->post("/assets", newAsset);

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: POST CREATE ASSET status = ",
            createResponse.statusCode);


        // 8. LOAN ASSET

        io:println("8. CLIENT -> POST /assets/CLIENT-TEST-001/loan");
        io:println("   CLIENT: Calling server...");

        http:Response loanResponse =
            check apiClient->post(
                "/assets/CLIENT-TEST-001/loan", "");

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: POST LOAN ASSET status = ",
            loanResponse.statusCode);


        // 9. ADD SCHEDULE


        io:println("9. CLIENT -> POST /assets/CLIENT-TEST-001/schedules");
        io:println("   CLIENT: Calling server...");

        json schedule = {
            scheduleId: "CLIENT-SCH-001",
            scheduleType: "MAINTENANCE",
            dueDate: "2026-12-01",
            description: "Maintenance created by Ballerina client"
        };

        http:Response scheduleResponse =
            check apiClient->post(
                "/assets/CLIENT-TEST-001/schedules",
                schedule);

        io:println("   SERVER: Response received.");
        io:println("   CLIENT: POST ADD SCHEDULE status = ",
            scheduleResponse.statusCode);


        // 10. VIEW SCHEDULE

        io:println("10. CLIENT -> GET /assets/CLIENT-TEST-001/schedules");
        io:println("    CLIENT: Calling server...");

        json schedules =
            check apiClient->get(
                "/assets/CLIENT-TEST-001/schedules");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: GET SCHEDULE successful.");
        io:println(schedules);


        // 11. ADD COMPONENT
    

        io:println("11. CLIENT -> POST /assets/CLIENT-TEST-001/components");
        io:println("    CLIENT: Calling server...");

        json component = {
            compId: "CLIENT-COMP-001",
            name: "Laptop Charger",
            description: "Charger added through Ballerina client"
        };

        http:Response componentResponse =
            check apiClient->post(
                "/assets/CLIENT-TEST-001/components",
                component);

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: POST ADD COMPONENT status = ",
            componentResponse.statusCode);



        // 12. VIEW COMPONENTS

        io:println("12. CLIENT -> GET /assets/CLIENT-TEST-001/components");
        io:println("    CLIENT: Calling server...");

        json components =
            check apiClient->get(
                "/assets/CLIENT-TEST-001/components");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: GET COMPONENTS successful.");
        io:println(components);


        // 13. OPEN WORK ORDER

        io:println("13. CLIENT -> POST /assets/CLIENT-TEST-001/workorders");
        io:println("    CLIENT: Calling server...");

        json workOrder = {
            orderId: "CLIENT-WO-001",
            description: "Maintenance work order created by client",
            status: "OPEN"
        };

        http:Response workOrderResponse =
            check apiClient->post(
                "/assets/CLIENT-TEST-001/workorders",
                workOrder);

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: POST WORK ORDER status = ",
            workOrderResponse.statusCode);


        // 14. ADD WORK-ORDER TASK

        io:println("14. CLIENT -> POST /assets/.../tasks");
        io:println("    CLIENT: Calling server...");

        json task = {
            taskId: "CLIENT-TASK-001",
            description: "Check laptop battery",
            status: "OPEN"
        };

        http:Response taskResponse =
            check apiClient->post(
                "/assets/CLIENT-TEST-001/workorders/CLIENT-WO-001/tasks",
                task);

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: POST TASK status = ",
            taskResponse.statusCode);

        // 15. VIEW WORK ORDERS

        io:println("15. CLIENT -> GET /assets/CLIENT-TEST-001/workorders");
        io:println("    CLIENT: Calling server...");

        json workOrders =
            check apiClient->get(
                "/assets/CLIENT-TEST-001/workorders");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: GET WORK ORDERS successful.");
        io:println(workOrders);


        // 16. VIEW WORK-ORDER TASKS

        io:println("16. CLIENT -> GET WORK-ORDER TASKS");
        io:println("    CLIENT: Calling server...");

        json tasks =
            check apiClient->get(
                "/assets/CLIENT-TEST-001/workorders/CLIENT-WO-001/tasks");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: GET TASKS successful.");
        io:println(tasks);


        // 17. CLOSE WORK ORDER

        io:println("17. CLIENT -> PUT WORK ORDER");
        io:println("    CLIENT: Calling server...");

        json closedWorkOrder = {
            orderId: "CLIENT-WO-001",
            description: "Maintenance work order completed",
            status: "CLOSED"
        };

        http:Response closeResponse =
            check apiClient->put(
                "/assets/CLIENT-TEST-001/workorders/CLIENT-WO-001",
                closedWorkOrder);

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: PUT CLOSE WORK ORDER status = ",
            closeResponse.statusCode);


        // 18. DELETE COMPONENT
        io:println("18. CLIENT -> DELETE COMPONENT");
        io:println("    CLIENT: Calling server...");

        http:Response deleteComponentResponse =
            check apiClient->delete(
                "/assets/CLIENT-TEST-001/components/CLIENT-COMP-001");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: DELETE COMPONENT status = ",
            deleteComponentResponse.statusCode);

        // 19. DELETE SCHEDULE
    
        io:println("19. CLIENT -> DELETE SCHEDULE");
        io:println("    CLIENT: Calling server...");

        http:Response deleteScheduleResponse =
            check apiClient->delete(
                "/assets/CLIENT-TEST-001/schedules/CLIENT-SCH-001");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: DELETE SCHEDULE status = ",
            deleteScheduleResponse.statusCode);


        // 20. DELETE TEST ASSET

        io:println("20. CLIENT -> DELETE /assets/CLIENT-TEST-001");
        io:println("    CLIENT: Calling server...");

        http:Response deleteAssetResponse =
            check apiClient->delete(
                "/assets/CLIENT-TEST-001");

        io:println("    SERVER: Response received.");
        io:println("    CLIENT: DELETE TEST ASSET status = ",
            deleteAssetResponse.statusCode);


io:println("21. CONCURRENCY DEMONSTRATION");


io:println("\n[CLIENT] Starting TWO requests concurrently...");

// Request A
http:HttpFuture assetsFuture =
    check apiClient->submit(
        "GET",
        "/assets",
        {});

// Request B
http:HttpFuture overdueFuture =
    check apiClient->submit(
        "GET",
        "/assets/overdue",
        {});

io:println("[CLIENT] Request A started: GET /assets");
io:println("[CLIENT] Request B started: GET /assets/overdue");

io:println("\n[CLIENT] Both requests are running concurrently.");

// Get response A
http:Response assetsResponse =
    check apiClient->getResponse(assetsFuture);

io:println("\n[CLIENT] Response A received.");
io:println("         GET /assets");
io:println("         Status: ", assetsResponse.statusCode);

// Get response B
http:Response overdueResponse =
    check apiClient->getResponse(overdueFuture);

io:println("\n[CLIENT] Response B received.");
io:println("         GET /assets/overdue");
io:println("         Status: ", overdueResponse.statusCode);

io:println("\n[CLIENT] BOTH CONCURRENT REQUESTS COMPLETED.");
        


    } on fail error err {

        io:println("              [CLIENT ERROR]");
        io:println("An error occurred: ", err.message());
        io:println("Details: ", err.detail());
    }
}