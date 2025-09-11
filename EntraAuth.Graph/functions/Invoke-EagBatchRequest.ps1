function Invoke-EagBatchRequest {
	<#
	.SYNOPSIS
		Executes a graph Batch requests, sending multiple requests in a single invocation.

	.DESCRIPTION
		Executes a graph Batch requests, sending multiple requests in a single invocation.
		This allows optimizing code performance, where iteratively sending requests does not scale.

		There are two ways to call this command:
		+ By providing the full request (by using the "-Request" parameter)
		+ By Providing a Path with placeholders and for multiple items calculate the actual url based on inserting the values into the placeholder positions (by using the "-Path" parameter)

		See the documentation on the respective parameters or the example on how to use them.

		Up to 20 requests can be sent in one batch, but this command will automatically split larger workloads into separate
		sets of 20 before sending them.

	.PARAMETER Request
		The requests to send. Provide either a url string or a request hashtables with any combination of the following keys:
		+ id:        The numeric ID to use. Determines the order in which requests are processed in the server end.
		+ method:    The REST method to use (GET, POST, PATCH, ...)
		+ url:       The relative url to call
		+ body:      The body to provide with the request
		+ headers:   Headers to include with the request
		+ dependsOn: The id of another request that must be successful, in order to run this request. Prevents executing requests invalidated by another request's failure.

		The only mandatory value to provide (whether as plain string or via hashtable) is the "url".
		The rest are filled by default values either provided via other parameters (Method, Body, Header) or the system (id) or omitted (dependsOn).

		In all cases, "url" should be the relative path - e.g. "users" - and NOT the absolute one (e.g. "https://graph.microsoft.com/v1.0/users")

		For more documentation on the properties, see the online documentation on batch requests:
		https://learn.microsoft.com/en-us/graph/json-batching

	.PARAMETER Path
		The path(s) to execute for each item in ArgumentList against.
		Example: "users/{0}/authentication/methods"
		Assuming a list of 50 user IDs, this will then insert the respective IDs into the url when building the request batches.
		After which it would execute the 50 paths in three separate batches (20 / 20 / 10 | Due to the 20 requests per batch limit enforced by the API).

		In combination with the "-Properties" parameter, it is also possible to insert multiple values per path.
		Example: "sites/{0}/lists/{1}/items?expand=fields"
		Assuming the parameter "-Properties" contains "'SiteID', 'ListID'" and the ArgumentList provides objects that contain those properties, this allows bulkrequesting all items from many lists in one batch.

		All requests generated from this parameter use the default Method, Body & Header provided via the parameters of the same name.

	.PARAMETER ArgumentList
		The list of values, for each of which for each "-Path" provided a request is sent.
		In combination with the "-Properties" parameter, you can also select one or more properties from these objects to format into the path,
		rather than inserting the full value of the argument.

	.PARAMETER Properties
		The properties from the arguments provided via "-ArgumentList" to format into the paths provided.
		This allows inserting multiple values into the request url.

	.PARAMETER Method
		The default method to use for batched requests, if not defined otherwise in the request.
		Defaults to "GET"

	.PARAMETER Body
		The default body to provide with batched requests, if not defined otherwise in the request.
		Defaults to not being specified at all.

	.PARAMETER Header
		The default header to provide with batched requests, if not defined otherwise in the request.
		Defaults to not being specified at all.

	.PARAMETER Timeout
		How long to retry batched requests that are being throttled.
		By default, requests are re-attempted until 5 minutes have expired (specifically, until the "notAfter" response would lead the next attempt beyond that time limit).
		Set to 0 minutes to never retry throttled requests.

	.PARAMETER Matched
		Rather than returning the results alone, match the results to the input object.
		This will create a custom object with ...
		- Id: The batch ID (generally cosmetic).
		- Argument: The value provided to "-ArgumentList" or - if using the "-Request" parameter instead - the finalized batch request entry.
		- Result: The return value (if any) or the error result.
		- Success: Boolean truth of whether the request was successful.

	.PARAMETER Raw
		Do not process the responses provided by the batched requests.
		This will cause the batching metadata to be included with the actual result data.
		This can be useful to correlate responses to the original requests.

	.PARAMETER ServiceMap
		Optional hashtable to map service names to specific EntraAuth service instances.
		Used for advanced scenarios where you want to use something other than the default Graph connection.
		Example: @{ Graph = 'GraphBeta' }
		This will switch all Graph API calls to use the beta Graph API.

	.EXAMPLE
		PS C:\> Invoke-EagBatchRequest -Path 'users/{0}/authentication/methods' -ArgumentList $users.id

		Retrieves the authentication methods for all users in $users

	.EXAMPLE
		PS C:\> Invoke-EagBatchRequest -Path 'users/{0}/authentication/methods' -ArgumentList $users.id -Matched

		Retrieves the authentication methods for all users in $users.
		Will return a set of objects, matching the authentication methods to the ID of the user.

	.EXAMPLE
		PS C:\> Invoke-EagBatchRequest -Path 'users/{0}/authentication/methods' -ArgumentList $users -Properties id -Matched

		Retrieves the authentication methods for all users in $users.
		Will return a set of objects, matching the authentication methods to the user object.

	.EXAMPLE
		PS C:\> Invoke-EagBatchRequest -Path 'users/{0}/authentication/methods' -ArgumentList $users -Properties id -ServiceMap GraphBeta

		Retrieves the authentication methods for all users in $users while using the GraphBeta EntraAuth service.

	.EXAMPLE
		PS C:\> Invoke-EagBatchRequest -Path 'sites/{0}/lists/{1}/items?expand=fields' -ArgumentList $lists -Properties SiteID, ListID

		Retrieves all the items from all lists in $lists.
		Assumes that each object in $lists has the properties "SiteID" and "ListID" (not case sensitive).

	.EXAMPLE
		PS C:\> $requests = @(
			@{
				url    = "users"
				method = "GET"
			},
			@{
				url     = "users?`$filter=country eq 'Denmark' and accountEnabled eq true and startswith(jobTitle, 'TECH') and onPremisesSyncEnabled eq true&`$select=id,displayName,userPrincipalName&`$expand=memberOf&`$count=true"
				method  = "GET"
				headers = @{
					"ConsistencyLevel" = "eventual"
					"Content-Type"     = "application/json"
				}
			},
			@{
				url     = "users"
				method  = "PATCH"
				body    = @{
					businessPhones = @(
						"+1 425 555 0109"
					)
					officeLocation = "18/2111"
				}
				headers = @{ "Content-Type" = "application/json" }
			},
			@{
				url    = "users/{user-id}"
				method = "DELETE"
			},
			@{
				url    = "groups"
				method = "POST"
				body   = @{
					description     = "Self help community for library"
					displayName     = "Library Assist"
					groupTypes      = @(
						"Unified"
					)
					mailEnabled     = $true
					mailNickname    = "library"
					securityEnabled = $false
				}
			},
			@{
				url     = "users/{user-id}/manager/´$ref"
				method  = "PUT"
				body    = @{
					"@odata.id" = "https://graph.microsoft.com/v1.0/users/{manager-id}"
				}
				headers = @{
					"Content-Type" = "application/json"
				}
			}
		)
		PS C:\> Invoke-EagBatchRequest -Request $requests -Method GET -Header @{ 'Content-Type' = 'application/json' }

		Executes all the requests provided in $requests, defaulting to the method "GET" and providing the content-type via header,
		unless otherwise specified in individual requests.
	.EXAMPLE
		PS C:\> $requests = @(
			@{ url = 'users/12345'; method = 'GET' },
			@{ url = 'users/67890'; method = 'GET' }
		)
		PS C:\> Invoke-EagBatchRequest -Request $requests -Method GET -Raw

	.LINK
		https://learn.microsoft.com/en-us/graph/json-batching
	#>
	[CmdletBinding(DefaultParameterSetName = 'Request')]
	param (
		[Parameter(Mandatory = $true, ParameterSetName = 'Request')]
		[object[]]
		$Request,

		[Parameter(Mandatory = $true, ParameterSetName = 'Path')]
		[string[]]
		$Path,

		[Parameter(Mandatory = $true, ParameterSetName = 'Path')]
		[object[]]
		$ArgumentList,

		[Parameter(ParameterSetName = 'Path')]
		[Alias('Property')]
		[string[]]
		$Properties,

		[Microsoft.PowerShell.Commands.WebRequestMethod]
		$Method = 'Get',

		[hashtable]
		$Body,

		[hashtable]
		$Header,

		[timespan]
		$Timeout = '00:05:00',

		[switch]
		$Matched,

		[switch]
		$Raw,

		[ArgumentCompleter({ (Get-EntraService | Where-Object Resource -Match 'graph\.microsoft\.com').Name })]
		[ServiceTransformAttribute()]
		[hashtable]
		$ServiceMap = @{}
	)
	begin {
		$services = $script:_serviceSelector.GetServiceMap($ServiceMap)
		Assert-EntraConnection -Cmdlet $PSCmdlet -Service $services.Graph

		$batchSize = 20 # Currently hardcoded API limit
		$includeFailed = $Raw -or $Matched

		function ConvertFrom-PathRequest {
			[CmdletBinding()]
			param (
				[string]
				$Path,

				[object[]]
				$ArgumentList,

				[AllowEmptyCollection()]
				[string[]]
				$Properties,

				[Microsoft.PowerShell.Commands.WebRequestMethod]
				$Method = 'Get',

				[hashtable]
				$Body,

				[hashtable]
				$Header,

				[hashtable]
				$Tracking
			)

			$index = 1
			foreach ($item in $ArgumentList) {
				# For later matching of result vs input
				$Tracking["$index"] = $item

				if (-not $Properties) { $values = $item }
				else {
					$values = foreach ($property in $Properties) {
						$item.$property
					}
				}

				$request = @{
					id     = "$index"
					method = "$Method".ToUpper()
					url    = $Path -f $values
				}
				if ($Body) { $request.body = $Body }
				if ($Header) { $request.headers = $Header }
				$request

				$index++
			}
		}
		function ConvertTo-BatchRequest {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "")]
			[CmdletBinding()]
			param (
				[object[]]
				$Request,

				[Microsoft.PowerShell.Commands.WebRequestMethod]
				$Method,

				$Cmdlet,

				[AllowNull()]
				[hashtable]
				$Body,

				[AllowNull()]
				[hashtable]
				$Header,

				[hashtable]
				$Tracking
			)
			$defaultMethod = "$Method".ToUpper()

			$results = @{}
			$requests = foreach ($entry in $Request) {
				$newRequest = @{
					url    = ''
					method = $defaultMethod
					id     = 0
				}
				if ($Body) { $newRequest.body = $Body }
				if ($Header) { $newRequest.headers = $Header }
				if ($entry -is [string]) {
					$newRequest.url = $entry
					$newRequest
					continue
				}

				if (-not $entry.url) {
					Invoke-TerminatingException -Cmdlet $Cmdlet -Message "Invalid batch request: No Url found! $entry" -Category InvalidArgument
				}
				$newRequest.url = $entry.url
				if ($entry.Method) {
					$newRequest.method = "$($entry.Method)".ToUpper()
				}
				if ($entry.id -as [int]) {
					$newRequest.id = $entry.id -as [int]
					$results[($entry.id -as [int])] = $newRequest
				}
				if ($entry.body) {
					$newRequest.body = $entry.body
				}
				if ($entry.headers) {
					$newRequest.headers = $entry.headers
				}
				if ($entry.dependsOn) {
					$newRequest.dependsOn
				}
				$newRequest
			}

			$index = 1
			$finalList = foreach ($requestItem in $requests) {
				if ($requestItem.id) {
					$requestItem.id = $requestItem.id -as [string]
					$requestItem
					continue
				}
				$requestItem.id = $requestItem.id -as [string]

				while ($results[$index]) {
					$index++
				}
				$requestItem.id = $index
				$results[$index] = $requestItem
				$requestItem
			}
			
			# For later matching of result vs input
			@($finalList).ForEach{ $Tracking[$_.id] = $Tracking }

			$finalList | Sort-Object { $_.id -as [int] }
		}
		function ConvertTo-BatchResult {
			[CmdletBinding()]
			param (
				$BatchEntry,

				[hashtable]
				$Tracking,

				[switch]
				$Raw
			)

			if ($Raw) { $result = $BatchEntry }
			elseif ($BatchEntry.Body.Value) { $result = $BatchEntry.Body.Value }
			else { $result = $BatchEntry.Body }

			[PSCustomObject]@{
				PSTypeName = 'EntraAuth.Graph.BatchResult'
				Id         = "$($BatchEntry.id)"
				Argument   = $Tracking["$($BatchEntry.id)"]
				Success    = $BatchEntry.status -match '^2'
				Result     = $result
			}

			$null = $Tracking.Remove("$($BatchEntry.id)")
		}
	}
	process {
		$tracking = @{ }
		if ($Request) { $batchRequests = ConvertTo-BatchRequest -Request $Request -Method $Method -Body $Body -Header $Header -Tracking $tracking -Cmdlet $PSCmdlet }
		else {
			$batchRequests = foreach ($pathEntry in $Path) {
				ConvertFrom-PathRequest -Path $pathEntry -ArgumentList $ArgumentList -Properties $Properties -Method $Method -Body $Body -Header $Header -Tracking $tracking
			}
		}

		$counter = [pscustomobject] @{ Value = 0 }
		$batches = $batchRequests | Group-Object -Property { [math]::Floor($counter.Value++ / $batchSize) } -AsHashTable

		foreach ($batch in ($batches.GetEnumerator() | Sort-Object -Property Key)) {
			Invoke-GraphBatch -ServiceMap $services -Batch $batch.Value -Start (Get-Date) -Timeout $Timeout -IncludeFailed:$includeFailed -Cmdlet $PSCmdlet | ForEach-Object {
				if ($Matched) { ConvertTo-BatchResult -BatchEntry $_ -Tracking $tracking -Raw:$Raw }
				elseif ($Raw) { $_ }
				elseif ($_.Body.Value) { $_.Body.Value }
				else { $_.Body }
			}
		}

		if (-not $Matched) { return }

		foreach ($pair in $tracking.GetEnumerator()) {
			[PSCustomObject]@{
				PSTypeName = 'EntraAuth.Graph.BatchResult'
				Id         = $pair.Key
				Argument   = $pair.Value
				Success    = $false
				Result     = $null
			}
		}
	}
}