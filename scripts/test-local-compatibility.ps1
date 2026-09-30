param([string]$SourceRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$script:checks = 0
function Require-Text([string]$RelativePath, [string]$Pattern) {
    $text = Get-Content -LiteralPath (Join-Path $SourceRoot $RelativePath) -Raw
    if ($text -notmatch $Pattern) { throw "Missing preserved behavior: $RelativePath / $Pattern" }
    $script:checks++
}
function Forbid-Text([string]$RelativePath, [string]$Pattern) {
    $text = Get-Content -LiteralPath (Join-Path $SourceRoot $RelativePath) -Raw
    if ($text -match $Pattern) { throw "Unsafe compatibility regression: $RelativePath / $Pattern" }
    $script:checks++
}
Require-Text 'cmake/dependencies/FetchRtxVideoSdk.cmake' 'RTX_VIDEO_SDK_LOCAL_ROOT'
Require-Text 'cmake/dependencies/rtx_video_adapter.cmake' 'RTX_VIDEO_ADAPTER_EXPECTED_SHA256'
Require-Text 'cmake/dependencies/rtx_video_adapter.cmake' 'RTX_VIDEO_RUNTIME_EXPECTED_SHA256'
Require-Text 'scripts/build-ds5-sidecar.ps1' '\$dotnet = @\(\$dotnetCommand\)\[0\]\.Source'
Require-Text 'src/entry_handler.cpp' 'SunshineCodexService'
Require-Text 'src/platform/windows/input.cpp' 'promote_automatic_to_dualsense\(gamepad_mode, metadata.type, metadata.capabilities, ds5_available\)'
Require-Text 'src/stream.cpp' 'server->iterate\(has_ds5_haptics_session \? 1ms :'
Require-Text 'src/video.cpp' 'cadence'
Require-Text 'src_assets/windows/misc/autostart/autostart-service.bat' 'SunshineCodexService'
foreach ($file in @('install-service.bat','uninstall-service.bat')) {
    $relative = "src_assets/windows/misc/service/$file"
    Require-Text $relative 'SunshineCodexService'
    Forbid-Text $relative '(?im)^\s*(?:sc|net)\s+(?:stop|delete)\s+"?(?:SunshineService|SunshineNetworkService)\b'
    Forbid-Text $relative '(?i)taskkill.*(?:sunshine\.exe|sunshinesvc\.exe)'
}
Require-Text 'tools/sunshinesvc.cpp' '#define SERVICE_NAME "SunshineCodexService"'
Require-Text 'tools/sunshinesvc.cpp' 'gui_agent_restart_policy.resume_supervision\(\)'
Forbid-Text 'tools/sunshinesvc.cpp' 'so never auto-launch it'
$preset = (Get-Content -LiteralPath (Join-Path $SourceRoot 'CMakePresets.json') -Raw | ConvertFrom-Json).configurePresets | Where-Object name -eq 'local-compat-release'
foreach ($pair in @(@('CMAKE_BUILD_TYPE','Release'), @('SUNSHINE_RTX_HDR','ON'), @('SUNSHINE_ENABLE_TRAY','ON'), @('SUNSHINE_ENABLE_LEGACY_TRAY','OFF'))) {
    if ($preset.cacheVariables.($pair[0]) -ne $pair[1]) { throw "Incorrect preservation preset: $($pair[0])" }
    $script:checks++
}
"PASS: $script:checks source/preset preservation checks (not hardware or installer execution)"
