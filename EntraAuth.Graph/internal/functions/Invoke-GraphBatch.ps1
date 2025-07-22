function Invoke-GraphBatch {
	<#
	.SYNOPSIS
		Executes a batch graph request.
	
	.DESCRIPTION
		Executes a batch graph request.
		Expects the batches to be presized to its natural limit (20) and correctly designed.

		This function calls itself recursively on throttled requests.
	
	.PARAMETER ServiceMap
		Optional hashtable to map service names to specific EntraAuth service instances.
		Used for advanced scenarios where you want to use something other than the default Graph connection.
		Example: @{ Graph = 'GraphBeta' }
		This will switch all Graph API calls to use the beta Graph API.
	
	.PARAMETER Batch
		The set of requests to send in one batch.
		Is expected to be no more than 20 requests.
		https://learn.microsoft.com/en-us/graph/json-batching
	
	.PARAMETER Start
		When the batch stop was started.
		This is matched against the timeout in case of throttled requests.
	
	.PARAMETER Timeout
		How long as a maximum we are willing to wait before giving up retries on throttled requests.
	
	.PARAMETER Cmdlet
		The $PSCmdlet variable of the calling command, to make sure all errors happen within the context of the caller
		and hence respect the ErrorActionPreference of the same.
	
	.EXAMPLE
		PS C:\> Invoke-GraphBatch -ServiceMap $services -Batch $batch.Value -Start (Get-Date) -Timeout '00:05:00' -Cmdlet $PSCmdlet

		Executes the provided requests in one bulk request, using the specified EntraAuth service connection.
		Will retry throttled requests for up to 5 minutes.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]
		$ServiceMap,

		[Parameter(Mandatory = $true)]
		[object[]]
		$Batch,

		[Parameter(Mandatory = $true)]
		[DateTime]
		$Start,

		[Parameter(Mandatory = $true)]
		[TimeSpan]
		$Timeout,

		[Parameter(Mandatory = $true)]
		$Cmdlet
	)
	process {
		$innerResult = try {
			(EntraAuth\Invoke-EntraRequest -Service $ServiceMap.Graph -Path '$batch' -Method Post -Body @{ requests = $Batch } -ContentType 'application/json' -ErrorAction Stop).responses
		}
		catch {
			$Cmdlet.WriteError(
				[System.Management.Automation.ErrorRecord]::new(
					[Exception]::new("Error sending batch: $($_.Exception.Message)", $_.Exception),
					"$($_.FullyQualifiedErrorId)",
					$_.CategoryInfo,
					@{ requests = $Batch }
				)
			)
			return
		}

		$throttledRequests = $innerResult | Where-Object status -EQ 429
		$failedRequests = $innerResult | Where-Object { $_.status -ne 429 -and $_.status -in (400..499) }
		$successRequests = $innerResult | Where-Object status -In (200..299)

		#region Handle Failed Requests
		foreach ($failedRequest in $failedRequests) {
			$Cmdlet.WriteError(
				[System.Management.Automation.ErrorRecord]::new(
					[Exception]::new("Error in batch request $($failedRequest.id): $($failedRequest.body.error.message)"),
					('{0}|{1}' -f $failedRequest.status, $failedRequest.error.code),
					[System.Management.Automation.ErrorCategory]::NotSpecified,
					($Batch | Where-Object { $_.ID -eq $failedRequest.id })
				)
			)
		}
		#endregion Handle Failed Requests

		#region Handle Successes
		if ($successRequests) {
			$successRequests
		}
		#endregion Handle Successes

		#region Handle Throttled Requests
		if (-not $throttledRequests) {
			return
		}

		$throttledOrigin = $Batch | Where-Object { $_.id -in $throttledRequests.id }
		$interval = ($throttledRequests.Headers | Sort-Object 'Retry-After' | Select-Object -Last 1).'Retry-After'
		$limit = $Start.Add($Timeout)
		
		if ((Get-Date).AddSeconds($interval) -ge $limit) {
			$Cmdlet.WriteError(
				[System.Management.Automation.ErrorRecord]::new(
					[Exception]::new("Retries for throttling exceeded, giving up on: $($throttledRequests.id -join ',')"),
					"ThrottlingRetriesExhausted",
					[System.Management.Automation.ErrorCategory]::LimitsExceeded,
					$throttledOrigin
				)
			)
			return
		}

		
		$Cmdlet.WriteVerbose("Throttled requests detected, waiting $interval seconds before retrying")
		Start-Sleep -Seconds $interval

		Invoke-GraphBatch -ServiceMap $ServiceMap -Batch $throttledOrigin -Start $Start -Timeout $Timeout -Cmdlet $Cmdlet
		#endregion Handle Throttled Requests
	}
}