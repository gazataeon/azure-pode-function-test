function Invoke-PodeEndware
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $WebEvent,

        [Parameter()]
        $Endware
    )

    # if there's no endware, do nothing
    if ($null -eq $Endware -or $Endware.Length -eq 0) {
        return
    }

    # loop through each of the endware, invoking the next if it returns true
    foreach ($eware in @($Endware))
    {
        try {
            Invoke-ScriptBlock -ScriptBlock $eware -Arguments $WebEvent -Scoped | Out-Null
        }
        catch {
            $Error[0] | Out-Default
        }
    }
}

function Endware
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [scriptblock]
        $ScriptBlock
    )

    # add the scriptblock to array of endware that needs to be run
    $PodeContext.Server.Endware += $ScriptBlock
}