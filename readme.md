# EntraAuth.Graph

Client tools for interacting with the Graph API.
This project has been based on the [EntraAuth](https://github.com/FriedrichWeinmann/EntraAuth) module, for lightweight convenient authentication and request handling.

## Installation

To install this module, run:

```powershell
Install-Module EntraAuth.Graph -Scope CurrentUser
```

Or using `PSFramework.NuGet`:

```powershell
# Bootstrap PSFramework.NuGet
Invoke-WebRequest https://raw.githubusercontent.com/PowershellFrameworkCollective/PSFramework.NuGet/refs/heads/master/bootstrap.ps1 | Invoke-Expression

# Install the module
Install-PSFModule EntraAuth.Graph
```

## Profit

> Retrieve all Authentication Methods for all users

```powershell
Connect-EntraService -ClientID Graph -Scopes user.readbasic.all, UserAuthenticationMethod.Read.All
$users = Invoke-EntraRequest -Path users
Invoke-EagBatchRequest -Path 'users/{0}/authentication/methods' -ArgumentList $users.id
```

> Retrieve all events from all calendars specified

```powershell
Invoke-EagBatchRequest -Path 'users/{0}/calendars/{1}/events' -ArgumentList $calData -Properties ID, User
```