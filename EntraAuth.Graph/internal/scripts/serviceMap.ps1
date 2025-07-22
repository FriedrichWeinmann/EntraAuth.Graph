$script:_services = @{
    Graph = 'Graph'
}

$script:_serviceSelector = New-EntraServiceSelector -DefaultServices $script:_services