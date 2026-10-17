@echo off
REM RAGame launcher / installer (Windows).
REM
REM Every run asks how the language model should run (OpenAI API key or local
REM Ollama) unless the user chose "don't ask again"; then it installs the needed
REM models and starts the backend and the game.
setlocal enabledelayedexpansion

set "APP_DIR=%~dp0"
set "CONFIG_DIR=%APPDATA%\raggame"
set "CONFIG_FILE=%CONFIG_DIR%\config.env"
set "BACKEND_BIN=%RAGAME_BACKEND_BIN%"
if "%BACKEND_BIN%"=="" set "BACKEND_BIN=%APP_DIR%backend\raggame-backend.exe"
set "GAME_BIN=%RAGAME_GAME_BIN%"
if "%GAME_BIN%"=="" set "GAME_BIN=%APP_DIR%game\ragame.exe"

set "EMBEDDING_MODEL=qwen3-embedding:4b"
set "CHAT_MODEL_LOCAL=gemma4:e4b"
set "CHAT_MODEL_API=gpt-6-luna"

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"

REM Elegir proveedor: se pregunta siempre, salvo "no volver a preguntar"
REM (RAGAME_ASK=0) guardado en la configuracion.
set "RAGAME_ASK=1"
if exist "%CONFIG_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do set "%%A=%%B"

set "SHOULD_ASK=1"
if exist "%CONFIG_FILE%" if "%RAGAME_ASK%"=="0" set "SHOULD_ASK=0"

if "%SHOULD_ASK%"=="1" (
	echo ==================================================
	echo   RAGame
	echo ==================================================
	echo Como queres ejecutar el modelo de lenguaje?
	echo   1^) Con una API key ^(OpenAI^)  [chat en la nube, embeddings locales]
	echo   2^) Localmente ^(Ollama^)       [todo en tu maquina]
	set /p OPT=Opcion [1/2]:
	if "!OPT!"=="2" (
		set "MODE=local"
		set "CHAT_PROVIDER=ollama"
		set "CHAT_MODEL=%CHAT_MODEL_LOCAL%"
		set "OPENAI_API_KEY="
	) else (
		set "MODE=api"
		set "CHAT_PROVIDER=openai"
		set "CHAT_MODEL=%CHAT_MODEL_API%"
		set /p OPENAI_API_KEY=Ingresa tu OPENAI_API_KEY:
	)
	set /p AGAIN=Volver a preguntar la proxima vez? [S/n]:
	if /i "!AGAIN!"=="n" ( set "RAGAME_ASK=0" ) else ( set "RAGAME_ASK=1" )
	(
		echo # Config de RAGame - borrar para reconfigurar.
		echo RAGAME_MODE=!MODE!
		echo RAGAME_ASK=!RAGAME_ASK!
		echo CHAT_PROVIDER=!CHAT_PROVIDER!
		echo CHAT_MODEL=!CHAT_MODEL!
		echo OPENAI_API_KEY=!OPENAI_API_KEY!
		echo EMBEDDING_MODEL=%EMBEDDING_MODEL%
		echo OLLAMA_URL=http://localhost:11434
	) > "%CONFIG_FILE%"
	echo Configuracion guardada en %CONFIG_FILE%
)

REM Carga la configuracion (eol=# ignora comentarios).
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do set "%%A=%%B"

where ollama >nul 2>nul
if errorlevel 1 (
	echo.
	echo Ollama no esta instalado.
	echo Descargalo de https://ollama.com/download e intenta de nuevo.
	pause
	exit /b 1
)

curl -s http://localhost:11434/api/tags >nul 2>nul
if errorlevel 1 (
	echo Iniciando Ollama ...
	start "ollama" /min ollama serve
	timeout /t 5 >nul
)

call :pull "%EMBEDDING_MODEL%"
if "%CHAT_PROVIDER%"=="ollama" (
	call :pull "%CHAT_MODEL%"
) else (
	echo Modo API: se omite la descarga del modelo de chat.
)

echo Iniciando backend ...
start "raggame-backend" /b "%BACKEND_BIN%"

set /a TRIES=0
:waitloop
curl -s http://localhost:8000/ >nul 2>nul
if not errorlevel 1 goto backendup
set /a TRIES+=1
if !TRIES! GEQ 60 (
	echo ERROR: el backend no respondio.
	pause
	exit /b 1
)
timeout /t 1 >nul
goto waitloop

:backendup
echo Iniciando el juego ...
"%GAME_BIN%"

taskkill /f /im raggame-backend.exe >nul 2>nul
endlocal
exit /b 0

:pull
ollama list | findstr /b /c:"%~1" >nul
if errorlevel 1 (
	echo Descargando %~1 ...
	ollama pull %~1
) else (
	echo %~1 ya instalado.
)
exit /b 0
