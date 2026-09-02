import ballerina/http;
import ballerina/io;

// ---------------------------------------------------------------------------
// Static hosting for the browser console (bonus web interface).
//
// It shares the listener with the API so the page is served from the same
// origin and can call `/library/...` directly with `fetch`.
//   http://localhost:8080/        -> staff console
//   http://localhost:8080/library -> REST API
//
// The file is read relative to the working directory, so start the service
// from inside the `question1-library-api` package directory.
// ---------------------------------------------------------------------------

const string UI_FILE = "resources/index.html";

service / on apiListener {

    resource function get .() returns http:Response|http:InternalServerError {
        return renderConsole();
    }

    resource function get console() returns http:Response|http:InternalServerError {
        return renderConsole();
    }
}

isolated function renderConsole() returns http:Response|http:InternalServerError {
    string|io:Error page = io:fileReadString(UI_FILE);
    if page is io:Error {
        http:InternalServerError serverError = {
            body: {
                code: "UI_UNAVAILABLE",
                message: "Could not read " + UI_FILE
                        + ". Start the service from inside the question1-library-api directory."
            }
        };
        return serverError;
    }
    http:Response response = new;
    response.setTextPayload(page, "text/html");
    return response;
}
