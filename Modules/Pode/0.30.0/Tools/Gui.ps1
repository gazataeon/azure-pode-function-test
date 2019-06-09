function Start-PodeGuiRunspace
{
    # do nothing if gui not enabled, or running as serverless
    if (!$PodeContext.Server.Gui.Enabled -or $PodeContext.Server.IsServerless) {
        return
    }

    $script = {
        try
        {
            # if there are multiple endpoints, flag warning we're only using the first - unless explicitly set
            if ($null -eq $PodeContext.Server.Gui.Endpoint)
            {
                if (($PodeContext.Server.Endpoints | Measure-Object).Count -gt 1) {
                    Write-Host "Multiple endpoints defined, only the first will be used for the GUI" -ForegroundColor Yellow
                }
            }

            # get the endpoint on which we're currently listening, or use explicitly passed one
            $endpoint = $PodeContext.Server.Gui.Endpoint
            if ($null -eq $endpoint) {
                $endpoint = $PodeContext.Server.Endpoints[0]
            }

            $protocol = (iftet $endpoint.Ssl 'https' 'http')

            # grab the port
            $port = $endpoint.Port
            if ($port -eq 0) {
                $port = (iftet $endpoint.Ssl 8443 8080)
            }

            $endpoint = "$($protocol)://$($endpoint.HostName):$($port)"

            # poll the server for a response
            $count = 0

            while ($true) {
                try {
                    Invoke-WebRequest -Method Get -Uri $endpoint -UseBasicParsing -ErrorAction Stop | Out-Null
                    if (!$?) {
                        throw
                    }

                    break
                }
                catch {
                    $count++
                    if ($count -le 50) {
                        Start-Sleep -Milliseconds 200
                    }
                    else {
                        throw "Failed to connect to URL: $($endpoint)"
                    }
                }
            }

            # import the WPF assembly
            [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | Out-Null
            [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore') | Out-Null

            # setup the WPF XAML for the server
            $gui_browser = "
                <Window
                    xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`"
                    xmlns:x=`"http://schemas.microsoft.com/winfx/2006/xaml`"
                    Title=`"$($PodeContext.Server.Gui.Name)`"
                    WindowStartupLocation=`"CenterScreen`"
                    ShowInTaskbar = `"$($PodeContext.Server.Gui.ShowInTaskbar)`"
                    WindowStyle = `"$($PodeContext.Server.Gui.WindowStyle)`">
                        <Window.TaskbarItemInfo>
                            <TaskbarItemInfo />
                        </Window.TaskbarItemInfo>
                        <WebBrowser Name=`"WebBrowser`"></WebBrowser>
                </Window>"

            # read in the XAML
            $reader = [System.Xml.XmlNodeReader]::new([xml]$gui_browser)
            $form = [Windows.Markup.XamlReader]::Load($reader)

            # set other options
            $form.TaskbarItemInfo.Description = $form.Title

            # add the icon to the form
            if (!(Test-Empty $PodeContext.Server.Gui.Icon)) {
                $icon = [Uri]::new($PodeContext.Server.Gui.Icon)
                $form.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($icon)
            }

            # set the state of the window onload
            if (!(Test-Empty $PodeContext.Server.Gui.State)) {
                $form.WindowState = $PodeContext.Server.Gui.State
            }

            # get the browser object from XAML and navigate to base page
            $form.FindName("WebBrowser").Navigate($endpoint)

            # display the form
            $form.ShowDialog() | Out-Null
            Start-Sleep -Seconds 1
        }
        catch {
            $Error[0] | Out-Default
            throw $_.Exception
        }
        finally {
            # invoke the cancellation token to close the server
            $PodeContext.Tokens.Cancellation.Cancel()
        }
    }

    Add-PodeRunspace -Type 'Gui' -ScriptBlock $script
}

function Gui
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('n')]
        [string]
        $Name,

        [Parameter()]
        [Alias('o')]
        [hashtable]
        $Options
    )

    # only valid for Windows PowerShell
    if (Test-IsPSCore) {
        throw 'The gui function is currently unavailable for PS Core, and only works for Windows PowerShell'
    }

    # enable the gui
    $PodeContext.Server.Gui.Enabled = $true
    $PodeContext.Server.Gui.Name = $Name

    # if we have options, set them up
    if (!(Test-Empty $Options)) {
        if (!(Test-Empty $Options.Icon)) {
            $PodeContext.Server.Gui['Icon'] = (Resolve-Path $Options.Icon).Path
        }

        if (!(Test-Empty $Options.ShowInTaskbar)) {
            $PodeContext.Server.Gui['ShowInTaskbar'] = $Options.ShowInTaskbar
        }

        if (!(Test-Empty $Options.State)) {
            $PodeContext.Server.Gui['State'] = $Options.State
        }

        if (!(Test-Empty $Options.WindowStyle)) {
            $PodeContext.Server.Gui['WindowStyle'] = $Options.WindowStyle
        }

        if (!(Test-Empty $Options.ListenName)) {
            $PodeContext.Server.Gui['ListenName'] = $Options.ListenName
        }
    }

    # validate the settings
    $icon = $PodeContext.Server.Gui.Icon
    if (!(Test-Empty $icon) -and !(Test-Path $icon)) {
        throw "Path to icon for GUI does not exist: $($icon)"
    }

    $state = $PodeContext.Server.Gui.State
    $states = @('Normal', 'Maximized', 'Minimized')
    if (!(Test-Empty $state) -and ($states -inotcontains $state)) {
        throw "Invalid GUI window state supplied, should be blank or one of $($states -join ' / ')"
    }

    $style = $PodeContext.Server.Gui.WindowStyle
    $styles = @('None', 'SingleBorderWindow', 'ThreeDBorderWindow', 'ToolWindow')
    if (!(Test-Empty $style) -and ($styles -inotcontains $style)) {
        throw "Invalid GUI window style supplied, should be blank or one of $($styles -join ' / ')"
    }

    # ensure a listen endpoint with name exists - if one has been passed
    if (!(Test-Empty $PodeContext.Server.Gui.ListenName)) {
        $found = ($PodeContext.Server.Endpoints | Where-Object {
            $_.Name -eq $PodeContext.Server.Gui.ListenName
        } | Select-Object -First 1)

        if ($null -eq $found) {
            throw "Listen endpoint with name '$($Name)' does not exist"
        }

        $PodeContext.Server.Gui['Endpoint'] = $found
    }
}