@echo off
chcp 65001 >nul
echo ========================================
echo   Drift Web 支持文件下载脚本
echo   下载 WasmDatabase 所需的必要文件
echo ========================================
echo.

set "WEB_DIR=%~dp0web"
set "SQLITE3_WASM_URL=https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.2/sqlite3.wasm"
set "DRIFT_WORKER_URL=https://github.com/simolus3/drift/releases/download/drift-2.33.0/drift_worker.js"

echo [1/4] 检查 web 目录...
if not exist "%WEB_DIR%" (
    echo ❌ 错误: 找不到 web 目录
    echo 请确保在 Flutter 项目根目录运行此脚本
    pause
    exit /b 1
)
echo ✅ web 目录存在: %WEB_DIR%
echo.

echo [2/4] 下载 sqlite3.wasm (SQLite WebAssembly 版本)...
echo    来源: %SQLITE3_WASM_URL%
powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SQLITE3_WASM_URL%' -OutFile '%WEB_DIR%\sqlite3.wasm' -UseBasicParsing }"
if %ERRORLEVEL% NEQ 0 (
    echo ❌ sqlite3.wasm 下载失败
    pause
    exit /b 1
)
echo ✅ sqlite3.wasm 下载成功
echo.

echo [3/4] 下载 drift_worker.js (Drift Web Worker)...
echo    来源: %DRIFT_WORKER_URL%
powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DRIFT_WORKER_URL%' -OutFile '%WEB_DIR%\drift_worker.js' -UseBasicParsing }"
if %ERRORLEVEL% NEQ 0 (
    echo ❌ drift_worker.js 下载失败
    pause
    exit /b 1
)
echo ✅ drift_worker.js 下载成功
echo.

echo [4/4] 验证文件...
for %%F in ("%WEB_DIR%\sqlite3.wasm" "%WEB_DIR%\drift_worker.js") do (
    if exist %%F (
        echo ✅ %%~nxF 存在 (%%~zF bytes)
    ) else (
        echo ❌ %%~nxF 缺失
        pause
        exit /b 1
    )
)

echo.
echo ========================================
echo   ✅ 所有文件下载完成！
echo ========================================
echo.
echo 你的 web 目录现在应该包含:
echo   web/
echo   ├── favicon.png
echo   ├── index.html
echo   ├── manifest.json
echo   ├── sqlite3.wasm          ← 新增 (SQLite WASM)
echo   └── drift_worker.js       ← 新增 (Drift Worker)
echo.
echo 现在可以运行:
echo   flutter run -d chrome     (Web 端测试)
echo   flutter run -d windows    (Windows 端测试)
echo.
pause
