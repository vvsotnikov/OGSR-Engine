# Shared by the live harness and offline evidence reader. No engine dependency.
function Assert-ValidationLogHealthy {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?im)^.*(?:FATAL ERROR|SCRIPT (?:RUNTIME )?ERROR|LUA ERROR).*$') {
        throw "Engine error during validation: $($Matches[0])"
    }
}
