function ConvertTo-BatchRequest {
	<#
	.SYNOPSIS
		Converts raw batch requests provided by the user into a task object.
	
	.DESCRIPTION
		Converts raw batch requests provided by the user into a task object.
		Needed for later task processing (especially paging).
		Task object will be added to the task-list provided.
	
	.PARAMETER Request
		The Request object to convert.
	
	.PARAMETER Parameters
		The parameters provided to the Invoke-EagBatchRequest.
	
	.PARAMETER TaskList
		The overall list of tasks to add the new task to.
	
	.PARAMETER Tracking
		Hashtable to track what batch request id was already assigned.
		Needs to be tracked to prevent accidentally assigning the same id multiple times.
	
	.EXAMPLE
		PS C:\> ConvertTo-BatchRequest -Request $requestItem -Parameters $parameters -TaskList $allTasks -Tracking $idTracking

		Converts the specified request item into a task object and adds it to $allTasks.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Request,

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
			Id         = $null
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
			Argument   = $Request
			Path       = $null
			Request    = $Request
			Parameters = $Parameters
		}

		#region ID
		if ($Request.id) {
			$task.Id = $Request.Id -as [int]
			if ($task.Id -gt $Tracking.CurrentID) { $Tracking.CurrentID = $task.Id + 1 }
		}
		else {
			while ($Tracking.CurrentID -in $TaskList.Id) {
				$Tracking.CurrentID++
			}
			$task.Id = $Tracking.CurrentID
		}
		$Tracking.CurrentID++
		#endregion ID

		#region Other Metadata
		if ($Request.Method) { $task.Method = $Request.Method }
		if ($Request.Body) { $task.Body = $Request.Body }
		if ($Request.Headers) { $task.Header = $Request.Headers }
		if ($Request -is [string]) { $task.Url = $Request }
		elseif ($Request.Url) { $task.Url = $Request.url }
		elseif ($Request -is [uri]) { $task.Url = $Request -as [string] }
		else { Invoke-TerminatingException -Cmdlet $Cmdlet -Message "Invalid batch request: No Url found! $Request" -Category InvalidArgument }
		if ($Request.DependsOn) { $task.DependsOn = $Request.DependsOn }
		#endregion Other Metadata

		$batch = @{
			id     = $task.Id -as [string]
			method = "$($task.Method)".ToUpper()
			url    = $task.Url
		}
		if ($task.Body) { $batch.body = $task.Body }
		if ($task.Header) { $batch.headers = $task.Header }
		if ($null -ne $task.DependsOn) { $batch.dependsOn = @($task.DependsOn) }
		$task.Batch = $batch

		$TaskList.Add($task)
	}
}