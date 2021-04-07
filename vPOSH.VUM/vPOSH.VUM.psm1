<#
	.SYNOPSIS
		VMware Update MAnager (VUM) Specific Functions
	.DESCRIPTION
		PowerCLI specific functions will have "[PowerCLI]" at the beginning of the Synopsis
#>

function Export-PatchBaseline
{
	<#
	.SYNOPSIS
		[PowerCLI]Exports a PatchBaseline from the currently connected vCenter to an XML file for offline transport.
	.DESCRIPTION
		Exports a PatchBaseline to an XML file for offline transport.  Useful when moving Baselines between 5.1 and 5.5 VUM instances
	.PARAMETER DestinationFile
		The file (full path) you wish to store the export
	.PARAMETER BaselineName
		The name of the PatchBaseline you want to Export
	.EXAMPLE
		Export-PatchBaseline -BaselineName "My Approved Patches" -DestinationFile \\someshare\somefolder\myFile.xml
	#>

	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true,Position=0)]
		[string]$DestinationFile,
		[Parameter(Mandatory=$true,Position=1)]
		[string]$BaselineName
	)

#	if($Host.Version -ne "2.0")
#	{
#		Invoke-Command -Credential $vCenterCredentials -ScriptBlock { Powershell.exe -Version 2 -noexit -command "Connect-VIServer $($global:DefaultVIServer.Name);Export-PatchBaseline '$($DestinationFile)' '$($BaselineName)'" }
#	}

	Get-PatchBaseline -Name $BaselineName | Export-Clixml -Path $DestinationFile
}

function Import-PatchBaseline
{
   <#
	.SYNOPSIS
		[PowerCLI]Imports a PatchBaseline to the currently connected vCenter from an XML file.
	.DESCRIPTION
		Imports a PatchBaseline to the currently connected vCenter from an XML file.  Useful when moving Baselines between 5.1 and 5.5 VUM instances
	.PARAMETER SourceFile
		The file (full path) you wish to restore the export
	.EXAMPLE
		Import-PatchBaseline -SourceFile \\someshare\somefolder\myFile.xml
	.NOTES
    	Author: Jody Whitlock
    	Date:   August 26, 2014
		LastModified: August 26, 2014
	#>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,

        [Parameter(Mandatory = $false)]
        [switch]$extension = $false
    )

    #Clear-Host

    $patchBaselineDest = Import-Clixml -Path $SourceFile
    $patches = $patchBaselineDest.CurrentPatches | % {Get-Patch -SearchPhrase $_.IdByVendor}
    $baseline = Get-PatchBaseline -Name $patchBaselineDest.Name -ErrorAction SilentlyContinue

    If ($baseline)
    {
        $baseline | Set-PatchBaseline -IncludePatch $patches
    }
    else
    {
        New-PatchBaseline -Name $patchBaselineDest.Name -Static -TargetType Host -IncludePatch $patches -Extension:$extension
    }
}

function Push-PatchBaseline
{
	<#
	.SYNOPSIS
		[PowerCLI]Pushes a PatchBaseline from one vCenter to another.
	.DESCRIPTION
		Easily allows for migration of a PatchBaseline from one vCenter to another.  For instance, migrating a PatchBaseline from a
		Test/Lab vCenter into a Production vCenter
	.PARAMETER SourcevCenter
		The vCenter you wish to copy the PatchBaseline from
	.PARAMETER DestinationvCenter
		The vCenter you wish to copy the PatchBaseline to
	.PARAMETER BaselineName
		The name of the PatchBaseline you want to copy
	.EXAMPLE
		Push-PatchBaseline -SourcevCenter TestvCenter -DestinationvCenter ProdvCenter -BaselineName "My Approved Patches"
	#>

	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$SourcevCenter,
		[Parameter(Mandatory=$true)]
		[string]$DestinationvCenter,
		[Parameter(Mandatory=$true)]
		[string]$BaselineName
	)

	Clear-Host

	Connect-vCenter -vCenter $SourcevCenter -ErrorAction Stop
	$patchBaselineSource = Get-PatchBaseline -Name $BaselineName

	Disconnect-VIServer -Server $SourcevCenter -Confirm:$false

	Connect-vCenter -vCenter $DestinationvCenter -ErrorAction Stop

	$results = @()
	foreach ($patch in $patchBaselineSource.CurrentPatches)
	{
		$results += Get-Patch -Server $DestinationvCenter -SearchPhrase $patch.IdByVendor
	}

	if(!(Get-PatchBaseline -Name $BaselineName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue))
	{
		if ($patchBaselineSource.BaselineContentType -eq "Static")
		{
			$patchBaselineDest = New-PatchBaseline -Static -Name $patchBaselineSource.Name -Description $patchBaselineSource.Description -IncludePatch $results -TargetType Host
		}
		else
		{
			$patchBaselineDest = New-PatchBaseline -Dynamic -Name $patchBaselineSource.Name -Description $patchBaselineSource.Description -IncludePatch $results -TargetType Host
		}

		$folder = Get-Inventory -Name IPN
		Attach-Baseline -Baseline $patchBaselineDest -Entity $folder
	}
	else
	{
		$patchBaselineDest = Get-PatchBaseline $BaselineName
		$patchBaselineDest | Set-PatchBaseline -IncludePatch $results -Description $patchBaselineSource.Description
	}

	Disconnect-VIServer -Server $DestinationvCenter -Confirm:$false
}

function Push-PatchApprovals
{
	<#
	.SYNOPSIS
		[PowerCLI]Pushes Patches from a Testing Baseline into an Approved Baseline on the same vCenter
	.DESCRIPTION
		Easily allows for migration of patches from a Testing Baseline to an Approved Baseline on the same vCenter
	.PARAMETER vCenter
		The vCenter you wish to operate on
	.PARAMETER TestBaselineName
		The name of the Test PatchBaseline you want to copy
	.PARAMETER ApprovedBaselineName
		The name of the Approved PatchBaseline you want to copy
	.EXAMPLE
		Push-PatchBaseline -vCenter TestvCenter -TestBaselineName "My Test Patches" -ApprovedBaselineName "My Approved Patches"
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$vCenter,
		[Parameter(Mandatory=$true)]
		[string]$TestBaselineName,
		[Parameter(Mandatory=$true)]
		[string]$ApprovedBaselineName
	)

	Clear-Host

	Connect-vCenter -vCenter $vCenter

	$patchBaselineSource=Get-PatchBaseline -Name $TestBaselineName

	$results = @()
	foreach ($patch in $patchBaselineSource.CurrentPatches)
	{
		$results += Get-Patch -SearchPhrase $patch.IdByVendor
	}

	if(!(Get-PatchBaseline -Name $ApprovedBaselineName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue))
	{
		if ($patchBaselineSource.BaselineContentType -eq "Static")
		{
			$patchBaselineDest = New-PatchBaseline -Static -Name $ApprovedBaselineName -Description "Approved Patches as of $(Get-Date)" -IncludePatch $results -TargetType Host
		}
		else
		{
			$patchBaselineDest = New-PatchBaseline -Dynamic -Name $ApprovedBaselineName -Description "Approved Patches as of $(Get-Date)" -IncludePatch $results -TargetType Host
		}

		$folder = Get-Inventory -Name IPN
		Attach-Baseline -Baseline $patchBaselineDest -Entity $folder
	}
	else
	{
		<#
		We have an existing Baseline, so when we call the Set-PatchBaseline it will not append so we need to read in
		the current patches as well as the new patches then set the baseline to the combined set.
		#>
		$patchBaselineDest = Get-PatchBaseline $ApprovedBaselineName
		foreach($patch in $patchBaselineDest.CurrentPatches)
		{
			$results += Get-Patch -SearchPhrase $patch.IdByVendor
		}
		$patchBaselineDest | Set-PatchBaseline -IncludePatch $results -Description "Approved Patches as of $(Get-Date)"
	}

	Disconnect-VIServer -Server $vCenter -Confirm:$false
}