function Set-EagConnection {
	<#
	.SYNOPSIS
		Defines the default EntraAuth service connection to use for commands in EntraAuth.Graph.
		
	.DESCRIPTION
		Defines the default EntraAuth service connection to use for commands in EntraAuth.Graph.
		By default, all requests use the default, builtin "Graph" service connection.

		This command allows redirecting all requests this module uses to use another service connection.
		However, be aware, that this change is Runspace-wide and may impact other modules using it.

		Modules that want to use this module are advised to instead use the "-ServiceMap" parameter
		that is provided on all comands executing Graph requests.
		For example, defining this during your module import will cause all subsequent requests you
		send to execute against the service connection you defined, without impacting anybody outside of your module:
		$PSDefaultParameterValues['*-Eag*:ServiceMap'] = @{ Graph = 'MyModule.Graph' }

		For more information on what service connections mean, see the readme of EntraAuth:
		https://github.com/FriedrichWeinmann/EntraAuth

		For more information on how to best build a module on EntraAuth, see the related documentation:
		https://github.com/FriedrichWeinmann/EntraAuth/blob/master/docs/building-on-entraauth.md
	
	.PARAMETER Graph
		What service connection to use by default.
	
	.EXAMPLE
		PS C:\> Set-EagConnection -Graph 'Corp.Graph'
		
		Sets the 'Corp.Graph' service connection as the default connection to use.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ArgumentCompleter({ (Get-EntraService).Name })]
        [string]
        $Graph
	)
	process {
		$script:_services.Graph = $Graph
	}
}