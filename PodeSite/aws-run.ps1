#Requires -Modules @{ModuleName='AWSPowerShell.NetCore';ModuleVersion='3.3.509.0'}
#Requires -Modules @{ModuleName='Pode';ModuleVersion='0.0.0'}

server -r $LambdaInput -rp '/tmp/www' {
    serverless 'aws-lambda'
    engine pode

    route get '/PodeSite' {
        view 'simple' -Data @{ 'numbers' = @(1, 2, 3); }
    }
}