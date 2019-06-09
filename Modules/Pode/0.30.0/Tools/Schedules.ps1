function Get-PodeSchedule
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    return $PodeContext.Schedules[$Name]
}

function Start-PodeScheduleRunspace
{
    if ((Get-PodeCount $PodeContext.Schedules) -eq 0) {
        return
    }

    $script = {
        # first, sleep for a period of time to get to 00 seconds (start of minute)
        Start-Sleep -Seconds (60 - [DateTime]::Now.Second)

        while ($true)
        {
            $_remove = @()
            $_now = [DateTime]::Now

            # select the schedules that need triggering
            $PodeContext.Schedules.Values |
                Where-Object {
                    ($null -eq $_.StartTime -or $_.StartTime -le $_now) -and
                    ($null -eq $_.EndTime -or $_.EndTime -ge $_now) -and
                    (Test-PodeCronExpressions -Expressions $_.Crons -DateTime $_now)
                } | ForEach-Object {

                # increment total number of triggers for the schedule
                if ($_.Countable) {
                    $_.Count++
                    $_.Countable = ($_.Count -lt $_.Limit)
                }

                # check if we have hit the limit, and remove
                if ($_.Limit -ne 0 -and $_.Count -ge $_.Limit) {
                    $_remove += $_.Name
                }

                try {
                    # trigger the schedules logic
                    Add-PodeRunspace -Type 'Schedules' -ScriptBlock (($_.Script).GetNewClosure()) `
                        -Parameters @{ 'Lockable' = $PodeContext.Lockable } -Forget
                }
                catch {
                    $Error[0]
                }

                # reset the cron if it's random
                $_.Crons = Reset-PodeRandomCronExpressions -Expressions $_.Crons
            }

            # add any schedules to remove that have exceeded their end time
            $_remove += @($PodeContext.Schedules.Values |
                Where-Object { ($null -ne $_.EndTime -and $_.EndTime -lt $_now) }).Name

            # remove any schedules
            $_remove | ForEach-Object {
                if ($PodeContext.Schedules.ContainsKey($_)) {
                    $PodeContext.Schedules.Remove($_)
                }
            }

            # cron expression only goes down to the minute, so sleep for 1min
            Start-Sleep -Seconds (60 - [DateTime]::Now.Second)
        }
    }

    Add-PodeRunspace -Type 'Main' -ScriptBlock $script
}

function Schedule
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Cron,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [scriptblock]
        $ScriptBlock,

        [Parameter()]
        [Alias('l')]
        [int]
        $Limit = 0,

        [Parameter()]
        [Alias('start', 's')]
        $StartTime = $null,

        [Parameter()]
        [Alias('end', 'e')]
        $EndTime = $null
    )

    # error if serverless
    Test-PodeIsServerless -FunctionName 'schedule' -ThrowError

    # lower the name
    $Name = $Name.ToLowerInvariant()

    # ensure the schedule doesn't already exist
    if ($PodeContext.Schedules.ContainsKey($Name)) {
        throw "Schedule called $($Name) already exists"
    }

    # ensure the limit is valid
    if ($Limit -lt 0) {
        throw "Schedule $($Name) cannot have a negative limit"
    }

    # ensure the start/end dates are valid
    if ($null -ne $EndTime -and $EndTime -lt [DateTime]::Now) {
        throw "Schedule $($Name) must have an EndTime in the future"
    }

    if ($null -ne $StartTime -and $null -ne $EndTime -and $EndTime -lt $StartTime) {
        throw "Schedule $($Name) cannot have a StartTime after the EndTime"
    }

    # add the schedule
    $PodeContext.Schedules[$Name] = @{
        'Name' = $Name;
        'StartTime' = $StartTime;
        'EndTime' = $EndTime;
        'Crons' = (ConvertFrom-PodeCronExpressions -Expressions @($Cron));
        'Limit' = $Limit;
        'Count' = 0;
        'Countable' = ($Limit -gt 0);
        'Script' = $ScriptBlock;
    }
}