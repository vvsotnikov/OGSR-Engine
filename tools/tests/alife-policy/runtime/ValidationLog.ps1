# The engine can exit with status zero after a fatal assertion. Always check
# the log as well as process status before accepting a gameplay capture.
# Shared by the live harness and offline evidence reader. No engine dependency.
function Assert-ValidationLogHealthy {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?im)^.*(?:FATAL ERROR|SCRIPT (?:RUNTIME )?ERROR|LUA ERROR|ExceptionCode\s*:|Scheduler tried to update object).*$') {
        throw "Engine error during validation: $($Matches[0])"
    }
}
