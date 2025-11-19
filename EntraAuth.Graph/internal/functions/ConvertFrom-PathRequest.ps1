function ConvertFrom-PathRequest {
	<#
	.SYNOPSIS
		Convert a combination of path and argument into a batch request task.
	
	.DESCRIPTION
		Convert a combination of path and argument into a batch request task.
	
	.PARAMETER Path
		The path to add argument data to.
	
	.PARAMETER Argument
		The argument to insert values from into the path.
	
	.PARAMETER Parameters
		The parameters provided to the Invoke-EagBatchRequest.
	
	.PARAMETER TaskList
		The overall list of tasks to add the new task to.
	
	.PARAMETER Tracking
		Hashtable to track what batch request id was already assigned.
		Needs to be tracked to prevent accidentally assigning the same id multiple times.
	
	.EXAMPLE
		PS C:\> ConvertFrom-PathRequest -Path $pathItem -Argument $argumentItem -Parameters $parameters -TaskList $allTasks -Tracking $idTracking

		Combines $pathItem and $argumentItem into a batch request task.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Path,
		
		[Parameter(Mandatory = $true)]
		$Argument,
		
		[Parameter(Mandatory = $true)]
		[hashtable]
		$Parameters,
		
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[System.Collections.Generic.List[object]]
		$TaskList,

		[hashtable]
		$Tracking
	)
	process {
		$task = [PSCustomObject]@{
			PSTypeName = 'EntraAuth.Graph.BatchTask'
			# Core Settings
			Id         = $Tracking.CurrentID
			Method     = $Parameters.Method
			Url        = $null
			Body       = $Parameters.Body
			Header     = $Parameters.Header
			DependsOn  = $null

			Batch      = $null

			# Operations
			Result     = @()
			Start      = $null
			WaitUntil  = $null
			WaitLimit  = $null

			# Metadata
			Argument   = $Argument
			Path       = $Path
			Request    = $null
			Parameters = $Parameters
		}
		$Tracking.CurrentID += 1
		$values = $Argument
		if ($Parameters.Properties) {
			$values = foreach ($property in $Parameters.Properties) {
				$Argument.$property
			}
		}
		$task.Url = $Path -f $values

		$batch = @{
			id     = $task.Id -as [string]
			method = "$($task.Method)".ToUpper()
			url    = $task.Url
		}
		if ($task.Body) { $batch.body = $task.Body }
		if ($task.Header) { $batch.headers = $task.Header }
		$task.Batch = $batch

		$TaskList.Add($task)
	}
}