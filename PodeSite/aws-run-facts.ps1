#Requires -Modules @{ModuleName='AWSPowerShell.NetCore';ModuleVersion='3.3.509.0'}
#Requires -Modules @{ModuleName='Pode';ModuleVersion='0.31.0'}

function Get-WindowsFacts {
    Get-Content /tmp/facts.json | ConvertFrom-Json
}

function Get-RandomFact {
    $Facts = Get-WindowsFacts
    $RandomNum = ((Get-Random -Minimum 0 -Maximum ($Facts).count) - 1)
    $Facts[$RandomNum]
}

function Get-FactCount {
    @{ 'Count' = (Get-WindowsFacts).Count; }
}

if (!(Test-Path /tmp/facts.json)) {
    Read-S3Object -BucketName "windowsfacts-cf" -Key facts.json -File /tmp/facts.json | Out-Null
}

server -r $LambdaInput {
    serverless 'aws-lambda'

    route get '/fact' {
        $Fact = Get-RandomFact 
        json @{
            Fact = $Fact
            CharLength = $Fact.length
        }
    }

    route get '/factcount' {
        json (Get-FactCount)
    }
}