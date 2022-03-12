# AzStorageTableEntity

For use in Azure Functions (Powershell) mainly, I have been using the [AzTable](https://github.com/paulomarquesc/AzureRmStorageTable) module. However recently I ran into the issue that this does not appear to support signing in through oauth. This means that signing in using a Managed Identity from the function app is not possible.

It appears this module is depending upon [Microsoft.Azure.Cosmos.Table](https://docs.microsoft.com/en-us/dotnet/api/microsoft.azure.cosmos.table?view=azure-dotnet) cloudTable. As far as my understanding goes, this does not support the [DefaultAzureCredential Class](https://docs.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential?view=azure-dotnet), though alternatively [Azure.Data.Tables](https://docs.microsoft.com/en-us/dotnet/api/azure.data.tables?view=azure-dotnet) does appear to support this (in preview).

Since I have a requirement to be able to use Manage Identity for authorizing access to an Azure Storage Table I needed to find a solution. Since my .Net 'Fu' is basically non-existent, I decided to instead look into using the [REST API](https://docs.microsoft.com/en-us/rest/api/storageservices/table-service-concepts) provided to gain access instead.

I created this module to allow relatively simpel manipulation of Azure Storage Tables. Bear in mind that I have currently only spot-tested the module and while it appears to do what is required, I do not give any guarantee on functionality. Use for your own risk!

That being said, this module will provide the following functions when imported:

- Get-StorageTableRow
- Get-StorageTableNextRow
- Remove-StorageTableRow
- Add-StorageTableRow
- Update-StorageTableRow

It should work with the following providers:

- Azure Storage Account, using:
   - Shared Key
   - Current Signed-in Credentials
- Azurite Development Storage, using:
    - Shared Key only






