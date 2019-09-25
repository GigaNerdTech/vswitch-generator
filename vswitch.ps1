# Create Virtual switch and add all port groups
# Written by Joshua Woleben
# Date: 8/21/2019

# Import PowerCLI
Import-Module VMware.VimAutomation.Core

# Create credential object
$user = Read-Host -Prompt "Enter the user for the vCenter host"
$password = Read-Host -Prompt "Enter the password for connecting to vSphere: " -AsSecureString

$vsphere_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$password -ErrorAction Stop

$vcenter_hosts = @("vcenter.example.com")

foreach ($vhost in $vcenter_hosts) {

    # Connect to vCenter
    Write-Output "Connecting to $vhost..."
    Connect-VIServer -Server $vhost -Credential $vsphere_creds -ErrorAction Stop

    # Get all physical hosts
    Write-Output "Gathering all physical hosts..."


    $physical_hosts = Get-VMHost -Server $vhost 

    Write-Host $physical_hosts


    # Loop through each physical host
    $physical_hosts | foreach-object {
           $p_host = $_


            $esx = ""
            $dc1=""
            $dc=""
            $netFolder=""
            $net_Folder=""
           # Create new Switch
           Write-Output ("Adding switch to " + $_.Name)
           New-VirtualSwitch -VMHost $_ -Name "VSwitch"
                      
           # Get network folder
           Write-Output "Creating new network folder..."
           $esx = $p_host | Get-View
           $esx.UpdateViewData()

           $dc1 = Get-Datacenter -VMHost $p_host | Get-View
           $dc1.UpdateViewData()

           $dc = Get-Datacenter -VMHost $p_host
           $netFolder = Get-View $dc1.NetworkFolder
           $net_Folder = Get-Folder -Type Network -Location $dc -NoRecursion
           New-Folder -Name ($p_host.Name + "-VPGs").ToString() -Location $net_Folder -Confirm:$false

           $new_folder = Get-Folder -Name ($p_host.Name + "-VPGs").ToString() | Get-View
           # Get all virtual port groups for current host
           $portgroups = Get-VirtualPortGroup -VMHost $_ | Where-Object { $_.Name -notmatch "DVUplink" -and $_.Name -notmatch "test" -and $_.Name -notmatch "VM Network" -and $_.Name -notmatch "Default Network" -and $_.ExtensionData.Config.DefaultPortConfig.Vlan.VlanId -ne $null -and ($_.ExtensionData.Config.DefaultPortConfig.Vlan.VlanId).GetType().FullName -eq "System.Int32" }

           # Add all port groups to new switch
           $portgroups | ForEach-Object {
                $name = ($_.Name + "-" +(Select-String -InputObject $p_host.Name -Pattern "(.*?)\.mhs\.int").Matches.Groups[1].Value)
                Write-Output ("Adding virtual port group " + $name + " to VSwitch...")
                New-VirtualPortGroup -Name $name -VirtualSwitch (Get-VirtualSwitch -Name "VSwitch" -VMHost $p_host) -VLanId $_.ExtensionData.Config.DefaultPortConfig.Vlan.VlanId -Confirm:$false 

                # Refresh view
                $view = (Get-View -ViewType Network -Filter @{"Name" = "$name"})
                while ($view -eq $null) {
                    sleep 2
                    $view = (Get-View -ViewType Network -Filter @{"Name" = "$name"})
                }
                $view.UpdateViewData()


                Write-Output "Moving to folder..."
                $list = New-Object VMware.Vim.ManagedObjectReference
                $list.type = ((Get-View -ViewType Network -Filter @{"Name" = "$name"}).MoRef | Select-String -Pattern "(.*?)-").Matches.Groups[1].Value
                $list.value = ((Get-View -ViewType Network -Filter @{"Name" = "$name"}).MoRef | Select-String -Pattern ".*?-(.*-.*)").Matches.Groups[1].Value


                $state = $new_folder.MoveIntoFolder_Task($list)
                $state.Value

                if ((Get-Task -Id ("Task-" + $state.Value)) -ne $null) {
                    while ((Get-Task -Id ("Task-" + $state.Value)).State -notmatch "success") {
                        sleep 2
                    }
                }
                   
          }

           
    }
    Disconnect-VIServer -Server $vhost -Confirm:$false

}