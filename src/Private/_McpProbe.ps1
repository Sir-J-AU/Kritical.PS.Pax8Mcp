function Invoke-KriticalPax8McpInitialize {
    <#
    .SYNOPSIS
        POSTs a JSON-RPC initialize to the Pax8 MCP endpoint with the token header.
    .OUTPUTS
        PSCustomObject { Ok, StatusCode, ServerName, ServerVersion, Error }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Token,
        [string] $Endpoint = 'https://mcp.pax8.com/v1/mcp',
        [int]    $TimeoutSec = 20
    )
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"krit-pax8mcp","version":"1.0"}}}'
    $headers = @{
        'Content-Type'='application/json'
        'Accept'='application/json, text/event-stream'
        'x-pax8-mcp-token'=$Token
    }
    try {
        $r = Invoke-WebRequest -Uri $Endpoint -Method Post -Body $body -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing
        $content = $r.Content
        $payload = $null
        if ($content -match 'data:\s*(\{.*\})') { $payload = $matches[1] | ConvertFrom-Json }
        elseif ($content -match '^\s*(\{.*\})\s*$') { $payload = $matches[1] | ConvertFrom-Json }
        return [pscustomobject]@{
            Ok            = ($r.StatusCode -eq 200 -and $payload -and $payload.result)
            StatusCode    = $r.StatusCode
            ServerName    = if ($payload) { $payload.result.serverInfo.name } else { $null }
            ServerVersion = if ($payload) { $payload.result.serverInfo.version } else { $null }
            Error         = $null
        }
    } catch {
        $sc = 0
        if ($_.Exception.Response) { $sc = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{
            Ok=$false; StatusCode=$sc; ServerName=$null; ServerVersion=$null; Error=$_.Exception.Message
        }
    }
}

function Get-KriticalPax8McpToolList {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Token,
        [string] $Endpoint = 'https://mcp.pax8.com/v1/mcp',
        [int]    $TimeoutSec = 20
    )
    $body = '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    $headers = @{
        'Content-Type'='application/json'
        'Accept'='application/json, text/event-stream'
        'x-pax8-mcp-token'=$Token
    }
    try {
        $r = Invoke-WebRequest -Uri $Endpoint -Method Post -Body $body -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing
        if ($r.Content -match 'data:\s*(\{.*\})') {
            $obj = $matches[1] | ConvertFrom-Json
            return [pscustomobject]@{
                Ok        = $true
                ToolCount = $obj.result.tools.Count
                Tools     = ($obj.result.tools | Select-Object -ExpandProperty name | Sort-Object)
            }
        }
        return [pscustomobject]@{ Ok=$false; ToolCount=0; Tools=@() }
    } catch {
        return [pscustomobject]@{ Ok=$false; ToolCount=0; Tools=@(); Error=$_.Exception.Message }
    }
}

function Test-KriticalPax8McpOAuthDiscovery {
    <#
    .SYNOPSIS
        Validates the OAuth-discovery endpoint is responding correctly. Read-only.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $DiscoveryUrl = 'https://mcp.pax8.com/.well-known/oauth-authorization-server',
        [int]    $TimeoutSec = 10
    )
    try {
        $r = Invoke-WebRequest -Uri $DiscoveryUrl -TimeoutSec $TimeoutSec -UseBasicParsing
        if ($r.StatusCode -ne 200) {
            return [pscustomobject]@{ Ok=$false; StatusCode=$r.StatusCode; Issuer=$null; Scopes=@() }
        }
        $meta = $r.Content | ConvertFrom-Json
        return [pscustomobject]@{
            Ok=$true
            StatusCode=200
            Issuer=$meta.issuer
            AuthorizeEndpoint=$meta.authorization_endpoint
            TokenEndpoint=$meta.token_endpoint
            RegistrationEndpoint=$meta.registration_endpoint
            Scopes=$meta.scopes_supported
            CodeChallengeMethods=$meta.code_challenge_methods_supported
        }
    } catch {
        return [pscustomobject]@{ Ok=$false; StatusCode=0; Issuer=$null; Scopes=@(); Error=$_.Exception.Message }
    }
}
