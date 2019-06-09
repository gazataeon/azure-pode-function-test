function Serverless
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('Azure-Functions', 'Aws-Lambda')]
        [string]
        $Type
    )

    $PodeContext.Server.IsServerless = $true
    $PodeContext.Threads = 1
    $PodeContext.Server.Type = $Type
}

function Start-PodeAzFuncServer
{
    param (
        [Parameter(Mandatory=$true)]
        $Data
    )

    # setup any inbuilt middleware that works for azure functions
    $inbuilt_middleware = @(
        (Get-PodePublicMiddleware),
        (Get-PodeRouteValidateMiddleware),
        (Get-PodeBodyMiddleware),
        (Get-PodeCookieMiddleware)
    )

    $PodeContext.Server.Middleware = ($inbuilt_middleware + $PodeContext.Server.Middleware)

    try
    {
        try
        {
            # get the request
            $request = $Data.Request

            # setup the response
            $response = New-Object -TypeName HttpResponseContext
            $response.StatusCode = 200
            $response.Headers = @{}

            # reset event data
            $WebEvent = @{}
            $WebEvent.OnEnd = @()
            $WebEvent.Auth = @{}
            $WebEvent.Response = $response
            $WebEvent.Request = $request
            $WebEvent.Lockable = $PodeContext.Lockable
            $WebEvent.Method = $request.Method.ToLowerInvariant()
            $WebEvent.Query = $request.Query
            $WebEvent.Protocol = ($request.Url -split '://')[0]
            $WebEvent.Endpoint = ((Get-PodeHeader -Name 'host') -split ':')[0]
            $WebEvent.ContentType = (Get-PodeHeader -Name 'content-type')
            $WebEvent.ErrorType = $null
            $WebEvent.Cookies = @{}
            $WebEvent.PendingCookies = @{}

            # set the path, using static content query parameter if passed
            if (![string]::IsNullOrWhiteSpace($request.Query['static-file'])) {
                $WebEvent.Path = $request.Query['static-file']
            }
            else {
                $WebEvent.Path = "/api/$($Data.sys.MethodName)"
            }

            # set pode in server response header
            Set-PodeServerHeader -Type 'Kestrel'

            # invoke middleware
            if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $PodeContext.Server.Middleware -Route $WebEvent.Path)) {
                # get the route logic
                $route = Get-PodeRoute -HttpMethod $WebEvent.Method -Route $WebEvent.Path -Protocol $WebEvent.Protocol `
                    -Endpoint $WebEvent.Endpoint -CheckWildMethod

                # invoke route and custom middleware
                if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $route.Middleware)) {
                    Invoke-ScriptBlock -ScriptBlock $route.Logic -Arguments $WebEvent -Scoped
                }
            }
        }
        catch {
            status 500 -e $_
            Write-Host $Error[0]
        }

        # invoke endware specifc to the current web event
        $_endware = ($WebEvent.OnEnd + @($PodeContext.Server.Endware))
        Invoke-PodeEndware -WebEvent $WebEvent -Endware $_endware

        # close and send the response
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]$response)
    }
    catch {
        Write-Host $Error[0]
        throw $_.Exception
    }
}

function Start-PodeAwsLambdaServer
{
    param (
        [Parameter(Mandatory=$true)]
        $Data
    )

    # setup any inbuilt middleware that works for aws lambda
    $inbuilt_middleware = @(
        (Get-PodePublicMiddleware),
        (Get-PodeRouteValidateMiddleware),
        (Get-PodeBodyMiddleware),
        (Get-PodeCookieMiddleware)
    )

    $PodeContext.Server.Middleware = ($inbuilt_middleware + $PodeContext.Server.Middleware)

    try
    {
        try
        {
            # get the request
            $request = $Data

            # setup the response
            $response = @{
                'StatusCode' = 200;
                'Headers' = @{};
                'Body' = [string]::Empty;
            }

            # reset event data
            $WebEvent = @{}
            $WebEvent.OnEnd = @()
            $WebEvent.Auth = @{}
            $WebEvent.Response = $response
            $WebEvent.Request = $request
            $WebEvent.Lockable = $PodeContext.Lockable
            $WebEvent.Path = $request.path
            $WebEvent.Method = $request.httpMethod.ToLowerInvariant()
            $WebEvent.Query = $request.queryStringParameters
            $WebEvent.Protocol = (Get-PodeHeader -Name 'X-Forwarded-Proto')
            $WebEvent.Endpoint = ((Get-PodeHeader -Name 'Host') -split ':')[0]
            $WebEvent.ContentType = (Get-PodeHeader -Name 'Content-Type')
            $WebEvent.ErrorType = $null
            $WebEvent.Cookies = @{}
            $WebEvent.PendingCookies = @{}

            # set pode in server response header
            Set-PodeServerHeader -Type 'Lambda'

            # invoke middleware
            if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $PodeContext.Server.Middleware -Route $WebEvent.Path)) {
                # get the route logic
                $route = Get-PodeRoute -HttpMethod $WebEvent.Method -Route $WebEvent.Path -Protocol $WebEvent.Protocol `
                    -Endpoint $WebEvent.Endpoint -CheckWildMethod

                # invoke route and custom middleware
                if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $route.Middleware)) {
                    Invoke-ScriptBlock -ScriptBlock $route.Logic -Arguments $WebEvent -Scoped
                }
            }
        }
        catch {
            status 500 -e $_
            Write-Host $Error[0]
        }

        # invoke endware specifc to the current web event
        $_endware = ($WebEvent.OnEnd + @($PodeContext.Server.Endware))
        Invoke-PodeEndware -WebEvent $WebEvent -Endware $_endware

        # close and send the response
        if (![string]::IsNullOrWhiteSpace($response.ContentType)) {
            Set-PodeHeader -Name 'Content-Type' -Value $response.ContentType
        }

        return (@{
            'statusCode' = $response.StatusCode;
            'headers' = $response.Headers;
            'body' = $response.Body;
        } | ConvertTo-Json -Depth 10 -Compress) 
    }
    catch {
        Write-Host $Error[0]
        throw $_.Exception
    }
}