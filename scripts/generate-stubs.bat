@echo off
REM --------------------------------------------------------------------------
REM Generates the Ballerina gRPC stub (rental_pb.bal) for the Question 2 server
REM and client from proto\rental.proto. Run once after cloning.
REM
REM   scripts\generate-stubs.bat
REM --------------------------------------------------------------------------
setlocal
set ROOT=%~dp0..
set PROTO=%ROOT%\proto\rental.proto

where bal >nul 2>nul
if errorlevel 1 (
    echo Ballerina ^("bal"^) is not on the PATH. Install Swan Lake from https://ballerina.io/downloads/
    exit /b 1
)

echo Generating stub for the server ...
call bal grpc --input "%PROTO%" --output "%ROOT%\question2-rental-server"

echo Generating stub for the client ...
call bal grpc --input "%PROTO%" --output "%ROOT%\question2-rental-client"

echo.
echo Done. Both Question 2 packages now contain rental_pb.bal.
endlocal
