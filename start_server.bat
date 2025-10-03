@echo off
echo Starting EVH Legal Chat Phoenix Server...
echo.

echo Checking dependencies...
mix deps.get

echo.
echo Compiling...
mix compile

echo.
echo Starting server...
mix phx.server

pause
