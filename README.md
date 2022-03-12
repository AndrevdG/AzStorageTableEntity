# AzStorageTableEntity

For use in Azure Functions (Powershell) mainly, I have been using the [AzTable](https://github.com/paulomarquesc/AzureRmStorageTable) module. However recently I ran into the issue that this does not appear to support signing in through oauth. This means that signing in using a Managed Identity from the function app is not possible.

It appears this module is depending upon [Microsoft.Azure.Cosmos.Table](https://docs.microsoft.com/en-us/dotnet/api/microsoft.azure.cosmos.table?view=azure-dotnet) cloudTable. As far as my understanding goes, this does not support the [DefaultAzureCredential Class](https://docs.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential?view=azure-dotnet), though alternatively [Azure.Data.Tables](https://docs.microsoft.com/en-us/dotnet/api/azure.data.tables?view=azure-dotnet) does appear to support this (in preview).

Since I have a requirement to be able to use Managed Identity for authorizing access to an Azure Storage Table I needed to find a solution. Since my .Net 'Fu' is basically non-existent, I decided to instead look into using the [REST API](https://docs.microsoft.com/en-us/rest/api/storageservices/table-service-concepts) provided to gain access instead.

I created this module to allow relatively simple manipulation of Azure Storage Tables. Bear in mind that I have currently only spot-tested the module and while it appears to do what is required, I do not give any guarantee on functionality. Use for your own risk!

That being said, this module will provide the following functions when imported:

- Get-StorageTableRow
- Get-StorageTableNextRow
- Remove-StorageTableRow
- Add-StorageTableRow
- Update-StorageTableRow

It should work with the following:

- Azure Storage Account, using:
   - Shared Key
   - Current Signed-in Credentials
- Azurite Development Storage, using:
    - Shared Key only

## General
Every function requires a 'table' parameter. This parameter is an object of type [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable](https://docs.microsoft.com/en-us/dotnet/api/microsoft.windowsazure.commands.common.storage.resourcemodel.azurestoragetable?view=az-ps-latest). An object of this type can be obtained by using [Get-AzStorageTablehttps://docs.microsoft.com/en-us/powershell/module/az.storage/get-azstoragetable?view=azps-7.3.0)
Every function requires a 'table' parameter. This parameter is an object of type [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable](https://docs.microsoft.com/en-us/dotnet/api/microsoft.windowsazure.commands.common.storage.resourcemodel.azurestoragetable?view=az-ps-latest). An object of this type can be obtained by using [Get-AzStorageTable]()

For instance:

```PowerShell
    $ctx = New-AzStorageContext -StorageAccountName MyStorageAccount -UseConnectedAccount
    $table = Get-AzStorageTable -Name MyTable -Context $ctx
```
In this example **_$table_** can be used in all the imported commands.

## Add-StorageTableRow
- **table**: object containing reference to the table and how to authorize (using shared key or using signed in credentials)
- **partitionKey**: string used for the [partition](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#partitionkey-property) used by this entity
- **rowKey**: string used for the [Rowkey](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#rowkey-property), which is a unique identifier for the row
- **property**: hashtable containing additional columns to be inserted. See the [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/inserting-and-updating-entities#constructing-the-json-feed) for more information
- **returnContent**: switch, if selected the command will return the inserted row

Used to insert rows into an Azure Storage Table. It will fail if you attempt to overwrite an existing row. 

See [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/insert-entity)

**_Example_**
```PowerShell
Add-StorageTableRow -table $table -partitionKey 'MyPartitionKey' -rowKey 'MyRowKey' -property @{"CustomerCode@odata.type" = "Edm.Guid"; "CustomerCode" = "c9da6455-213d-42c9-9a79-3e9149a57833"}
```

## Update-StorageTableRow
- **table**: object containing reference to the table and how to authorize (using shared key or using signed in credentials)
- **partitionKey**: string used for the [partition](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#partitionkey-property) used by this entity
- **rowKey**: [Rowkey](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#rowkey-property) is a unique identifier for the row
- **property**: hashtable containing additional columns to be inserted. See the [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/inserting-and-updating-entities#constructing-the-json-feed) for more information

Used to insert or update a row into an Azure Storage Table.

See [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/update-entity2)

**_Example_**
```PowerShell
Update-StorageTableRow -table $table -partitionKey 'MyPartitionKey' -rowKey 'MyRowKey' -property @{"CustomerCode@odata.type" = "Edm.Guid"; "CustomerCode" = "c9da6455-213d-42c9-9a79-3e9149a57833"}
```

## Get-StorageTableRow
- **table**: object containing reference to the table and how to authorize (using shared key or using signed in credentials)
- **partitionKey**: string used for the [partition](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#partitionkey-property) used by this entity
- **rowKey**: [Rowkey](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#rowkey-property) is a unique identifier for the row. Can only be used in combination with _partionKey_
- **customFilter**: custom odata filter to select records from the Azure Storage Table. Cannot be used together with _partitionKey_ or _rowKey_ parameters
- **selectColumn**: comma separated list of columns that should be returned
- **top**: integer, maximum number of rows to be returned at once. If more records are found, a paginationQuery property will be added, which can be used by **_Get-StorageTableNextRow_** to retrieve the next set of records

Used to retrieve records from the Azure Storage Table

See [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/query-entities)

**_Example: Retrieve all records_**
```PowerShell
Get-StorageTableRow -table $table
```

**_Example: Retrieve records with partitionKey_**
```PowerShell
Get-StorageTableRow -table $table -partitionKey "MyPartition"
```

**_Example: Retrieve records with partitionKey and rowKey_**
```PowerShell
Get-StorageTableRow -table $table -rowKey "MyRowKey1" -partitionKey "MyPartition"
```

**_Example: Retrieve records with a custom odata filter_**
```PowerShell
Get-StorageTableRow -table $table -customFilter "RowKey eq 'MyRowKey1'"
```

**_Example: Retrieve the first 10 records (can be combined with all the other options)_**
```PowerShell
Get-StorageTableRow -table $table -top 10
```
_Note: top just limits the resultset to the first x records returned and can be used to paginate results_

**_Example: Select columns which are returned (can be combined with all the other options)_**
```PowerShell
Get-StorageTableRow -table $table -partitionKey "MyPartition" -selectColumn RowKey
```
_Note: selectColumn is case sensitive. rowKey(wrong) and RowKey(correct) are not the same!_
## Get-StorageTableNextRow
- **table**: object containing reference to the table and how to authorize (using shared key or using signed in credentials)
- **paginationQuery**: property of a paginated resultset, which contains the original filter and RowKey and PartitionKey for the next resultset

**_Example: Retrieve the first 10 records (can be combined with all the other options)_**
```PowerShell
# Retrieve the first set of results
$result = Get-StorageTableRow -table $table -top 10

# Retrieve the next set of results
$result = Get-StorageTableNextRow -table $table -paginationQuery $result.paginationQuery
```
_As long as the result includes a **paginationQuery** property, more results can be retrieved_

## Remove-StorageTableRow
- **table**: object containing reference to the table and how to authorize (using shared key or using signed in credentials)
- **partitionKey**: string used for the [partition](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#partitionkey-property) used by this entity
- **rowKey**: [Rowkey](https://docs.microsoft.com/en-us/rest/api/storageservices/understanding-the-table-service-data-model#rowkey-property) is a unique identifier for the row

Used to remove a row from the Azure Storage Table

**_Example_**
```PowerShell
Remove-StorageTableRow -table $table -partitionKey 'MyPartitionKey' -rowKey 'MyRowKey'
```

See [Microsoft Documentation](https://docs.microsoft.com/en-us/rest/api/storageservices/delete-entity1)





