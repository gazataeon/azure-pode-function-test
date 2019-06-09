# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$endpoint = '/api/PodeSite'

#Write-Host ($TriggerMetadata | ConvertTo-Json)

# Run it
server -r $TriggerMetadata -RootPath '../www' {
    serverless 'azure-functions'
    engine pode

    route get $endpoint {
        param($e)
        view 'simple' -Data @{ 'numbers' = @(1, 2, 3); }
    }

    route post $endpoint {
        param($e)
        Write-Host (root)
        text "Hello $($e.Data.Name)"
    }
}


<#server -r $TriggerMetadata -RootPath '../www' {
    serverless 'azure-functions'
    engine pode

    cookie secrets global 'rem'
    middleware (csrf -c middleware)

    route get $endpoint {
        $token = (csrf token)
        view 'index-csrf' -fm @{ 'csrfToken' = $token }
    }

    route post $endpoint {
        redirect '/api/PodeSite'
    }
}#>


<#server -r $TriggerMetadata -RootPath '../www' {
    serverless 'azure-functions'
    engine pode

    # setup session details
    middleware (session @{
        'Secret' = 'schwifty';
        'Duration' = 120;
        'Extend' = $true;
    })

    route get $endpoint {
        param($e)

        $e.Session.Data.Views++
        flash add 'current-date' ([datetime]::UtcNow)

        view -fm 'auth-home' -data @{
            'Views' = $e.Session.Data.Views;
        }
    }
}#>