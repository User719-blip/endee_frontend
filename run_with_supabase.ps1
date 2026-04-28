# PowerShell script to run Flutter app with Supabase credentials
# Usage: .\run_with_supabase.ps1

param(
    [string]$supabaseUrl = "https://bycbdjkeumwcwzraitpq.supabase.co",
    [string]$supabaseAnonKey = "sb_publishable_OaRBprYnXGRJ0bvm1k2l-g_s_QqIytF",
    [string]$pyBackendUrl = "http://127.0.0.1:8000",
    [string]$device = "chrome"
)

Write-Host "Starting Flutter app with Supabase credentials..." -ForegroundColor Green

if ($supabaseUrl -eq "https://sukxolpjeagqybohmjdk.supabase.co") {
    Write-Host "`nWARNING: Using default/placeholder Supabase URL!" -ForegroundColor Yellow
    Write-Host "Please provide your actual credentials:" -ForegroundColor Yellow
    Write-Host "  .\run_with_supabase.ps1 -supabaseUrl 'https://xyz.supabase.co' -supabaseAnonKey 'eyJ...'" -ForegroundColor Cyan
    Write-Host "`nOr create a .env.flutter file and source it first.`n" -ForegroundColor Yellow
}

Write-Host "Command: flutter run -d $device --dart-define SUPABASE_URL=*** --dart-define SUPABASE_ANON_KEY=*** --dart-define PY_BACKEND_URL=$pyBackendUrl`n" -ForegroundColor Cyan

$flutterArgs = @(
    "run",
    "-d", $device,
    "--dart-define", "SUPABASE_URL=$supabaseUrl",
    "--dart-define", "SUPABASE_ANON_KEY=$supabaseAnonKey",
    "--dart-define", "PY_BACKEND_URL=$pyBackendUrl"
)

& flutter @flutterArgs
