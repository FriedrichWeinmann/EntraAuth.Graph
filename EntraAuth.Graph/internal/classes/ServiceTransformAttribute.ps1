class ServiceTransformAttribute : System.Management.Automation.ArgumentTransformationAttribute {
	[object] Transform([System.Management.Automation.EngineIntrinsics] $Intrinsics, [object] $InputData) {
		if ($null -eq $InputData) {
			return @{ Graph = 'Graph' }
		}
		if ($InputData -is [hashtable]) {
			return $InputData
		}
		if ($InputData -is [string]) {
			return @{ Graph = $InputData }
		}
		if ($InputData.Graph) {
			return @{ Graph = $InputData.Graph }
		}
		return @{ Graph = $InputData -as [string] }
	}
}