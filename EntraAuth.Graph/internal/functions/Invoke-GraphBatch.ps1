function Invoke-GraphBatch {
	<#
	.SYNOPSIS
		Executes a batch graph request.
	
	.DESCRIPTION
		Executes a batch graph request.
		Expects the batches to be presized to its natural limit (20) and correctly designed.

	.PARAMETER Tasks
		The tasks to execute.
		Expects the result objects of either ConvertFrom-PathRequest or ConvertTo-BatchRequest.

	.PARAMETER TaskList
		The entire list of tasks that need batching.
		Tasks that have completed - including any paging that needs doing - should be removed from this list.

	.PARAMETER ServiceMap
		Hashtable to map service names to specific EntraAuth service instances.
		Used for advanced scenarios where you want to use something other than the default Graph connection.
		Example: @{ Graph = 'GraphBeta' }
		This will switch all Graph API calls to use the beta Graph API.

	.PARAMETER Cmdlet
		The $PSCmdlet variable of the calling command, to make sure all errors happen within the context of the caller
		and hence respect the ErrorActionPreference of the same.

	.EXAMPLE
		PS C:\> Invoke-GraphBatch -Tasks $tasks -TaskList $allTasks -ServiceMap $services -Cmdlet $PSCmdlet

		Executes all tasks in $tasks
	#>
	[CmdletBinding()]
	param (
		[object[]]
		$Tasks,

		[System.Collections.Generic.List[object]]
		$TaskList,

		[hashtable]
		$ServiceMap,

		[Parameter(Mandatory = $true)]
		$Cmdlet
	)
	process {
		$start = Get-Date
		$innerResult = try {
			(EntraAuth\Invoke-EntraRequest -Service $ServiceMap.Graph -Path '$batch' -Method Post -Body @{ requests = @($Tasks.Batch) } -ContentType 'application/json' -ErrorAction Stop).responses
		}
		catch {
			# This should happen only for bad requests (insufficient or bad request data), as otherwise the error is within the respective results on the individual batch members
			$Cmdlet.WriteError(
				[System.Management.Automation.ErrorRecord]::new(
					[Exception]::new("Error sending batch: $($_.Exception.Message)", $_.Exception),
					"$($_.FullyQualifiedErrorId)",
					$_.CategoryInfo.Category,
					@{ requests = @($Tasks.Batch) }
				)
			)
			# Remove workload to prevent infinite loop
			foreach ($task in $Tasks) { $null = $TaskList.Remove($task) }
			return
		}

		foreach ($result in $innerResult) {
			$task = @($Tasks).Where{ $_.batch.id -eq $result.id }[0]
			if (-not $task.Start) {
				$task.Start = $start
				$task.WaitLimit = $start.Add($task.Parameters.Timeout)
			}

			#region Case: Success
			if (200 -le $result.status -and 299 -ge $result.status) {
				# Update for paging or complete task
				if ($result.body.'@odata.nextLink' -and -not $task.Parameters.NoBatching) {
					$task.Batch.url = ($result.body.'@odata.nextLink' -replace '^https://' -split '/',3)[-1]
				}
				else { $null = $TaskList.Remove($task) }

				# Raw Output
				if ($task.Parameters.Raw) {
					$result
					continue
				}

				# Matched Output
				if ($task.Parameters.Matched) {
					$data = $result.body
					if ($data.PSObject.Properties.Name -contains 'value') { $data = $data.Value }
					if (-not $task.Result) { $task.Result = @($data) }
					else { $task.Result = $task.Result + @($data) }
					
					# Only return matched result after completing the batching
					if ($result.body.'@odata.nextLink') { continue }

					[PSCustomObject]@{
						PSTypeName = 'EntraAuth.Graph.BatchResult'
						Id         = "$($task.Id)"
						Argument   = $task.Argument
						Success    = $true
						Result     = $task.Result
						Status     = $result.status
					}
					continue
				}

				# Plain Output
				if ($result.body.PSObject.Properties.Name -contains 'value') { $result.body.value }
				else { $result.body }

				continue
			}
			#endregion Case: Success
			#region Case: Throttled
			if (429 -eq $result.status) {
				$task.WaitUntil = (Get-Date).AddSeconds($result.Headers.'Retry-After')
				continue
			}
			#endregion Case: Throttled
			#region Case: Failed
			if (400 -le $result.status -and 499 -ge $result.Status ) {
				$null = $TaskList.Remove($task)

				if ($task.Parameters.Raw) {
					$result
					continue
				}

				$Cmdlet.WriteError(
					[System.Management.Automation.ErrorRecord]::new(
						[Exception]::new("Error in batch request $($result.id): $($result.body.error.message)"),
						('{0}|{1}' -f $result.status, $result.error.code),
						[System.Management.Automation.ErrorCategory]::NotSpecified,
						$task.Batch
					)
				)

				if ($task.Parameters.Matched) {
					[PSCustomObject]@{
						PSTypeName = 'EntraAuth.Graph.BatchResult'
						Id         = "$($task.Id)"
						Argument   = $task.Batch
						Success    = $false
						Result     = $result.error
						Status     = $result.status
					}
				}
				continue
			}
			#endregion Case: Failed
			#region Case: Other
			$null = $TaskList.Remove($task)

			if ($task.Parameters.Raw) {
				$result
				continue
			}

			if ($task.Parameters.Matched) {
				[PSCustomObject]@{
					PSTypeName = 'EntraAuth.Graph.BatchResult'
					Id         = "$($task.Id)"
					Argument   = $task.Batch
					Success    = $false
					Result     = $result
					Status     = $result.status
				}
				continue
			}

			Write-Warning "Unexpected response code: $($result.status) on request id $($result.Id) ($($task.Url))"
			#endregion Case: Other
		}
	}
}