
function _signHMACSHA256 {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]
        $message,

        [Parameter(Mandatory=$true)]
        [string]
        $secret
    )

    Write-Verbose "Starting function _signHMACSHA256"

    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Convert]::FromBase64String($secret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::UTF8.GetBytes($message))
    $signature = [Convert]::ToBase64String($signature)

    return $signature
}

function _createRequestParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(Mandatory=$true)]
        [validateset('Get', 'Post', 'Put', 'Delete')]
        [string]
        $method,

        [Parameter(Mandatory=$false)]
        [string]
        $uriPathExtension = ''
    )

    Write-Verbose "Starting function _createRequestParameters"

    # Get the timestamp for the request
    $date = (Get-Date).ToUniversalTime().toString('R')

    # default connection object properties
    $connectionObject = @{
        method = $method
        uri = ("{0}{1}" -f $table.Uri, $uriPathExtension)
        contentType = "application/json"
        headers = @{ 
            "x-ms-date" = $date
            "x-ms-version" = "2021-04-10"
            "Accept" = "application/json;odata=nometadata"
        }
    }

    # If the table object contains credentials, use these (sharedkey) else use current logged in credentials
    if ($table.Context.TableStorageAccount.Credentials) {
        Write-Verbose "Using SharedKey for authentication"
        # See: https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
        if ($table.Context.StorageAccountName -eq "devstoreaccount1"){
            # if the storage emulator is used, the accountname appears twice in the string to sign
            Write-Verbose "Using development storage"
            $stringToSign = ("{0}`n`napplication/json`n{1}`n/{2}/{3}/{4}{5}" -f $method.ToUpper(), $date, $table.TableClient.AccountName, $table.TableClient.AccountName, $table.TableClient.Name, $uriPathExtension)
        } else {
            $stringToSign = ("{0}`n`napplication/json`n{1}`n/{2}/{3}{4}" -f $method.ToUpper(), $date, $table.TableClient.AccountName, $table.TableClient.Name, $uriPathExtension)
        }
        Write-Debug "Outputting stringToSign"
        $stringToSign.Replace("`n", "\n") | Out-String | Write-Debug
        $signature = _signHMACSHA256 -message $stringToSign -secret $table.Context.TableStorageAccount.Credentials.Key
        $connectionObject.headers += @{
            "Authorization" = ("SharedKey {0}:{1}" -f $table.TableClient.AccountName, $signature)
            "Date" = $date
        }
    } else {
        # See https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-azure-active-directory
        $connectionObject.headers += @{
            "Authorization" = "Bearer " + (ConvertFrom-SecureString -SecureString (Get-AzAccessToken -ResourceTypeName Storage -AsSecureString).token -AsPlainText)
        }
    }

    return $connectionObject
}

function _createBody {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]
        $partitionKey,

        [Parameter(Mandatory=$true)]
        [string]
        $rowKey,

        [Parameter(Mandatory=$false)]
        [hashTable]$property = @{}
    )

    Write-Verbose "Starting function _createBody"

    return ($property + @{
        "PartitionKey" = $partitionKey
        "RowKey" = $rowKey
    }) | ConvertTo-Json
}

function _processResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Object]
        $result,

        [Parameter(Mandatory=$false)]
        [string]
        $filterString=""
    )

    Write-Verbose "Starting function _processResult"

    [string]$paginationQuery=""
    # If netxPartition header is found, the query contains multiple pages
    if ($result.Headers.'x-ms-continuation-NextPartitionKey'){
        Write-Verbose "Result is paginated, creating paginationQuery to allow getting the next page"
        if ($filterString){
            $paginationQuery = ("{0}&NextPartitionKey={1}" -f $filterString, $result.Headers.'x-ms-continuation-NextPartitionKey'[0])
        } else {
            $paginationQuery = ("?NextPartitionKey={0}" -f $result.Headers.'x-ms-continuation-NextPartitionKey'[0])
        }
    }

    # nextRowKey header can be empty in some cases
    if ($result.Headers.'x-ms-continuation-NextRowKey') {
        $paginationQuery += ("&NextRowKey={0}" -f $result.Headers.'x-ms-continuation-NextRowKey'[0])
    }

    # Output results in debug
    Write-Debug "Outputting result object"
    $result | Out-String | Write-Debug
    $result.Headers | Out-String | Write-Debug

    Write-Verbose "Processing result.Content, if any"
    $returnValue = $result.Content | ConvertFrom-Json -Depth 99
    
    # Add pagination query to return if any. Allows fetching next pages when output is paginated
    if ($paginationQuery) {
        $paginationQuery | Out-String | Write-Debug
        Write-Debug "Outputting paginationQuery"
        $returnValue | Add-Member -MemberType NoteProperty -Name 'paginationQuery' -Value $paginationQuery
    }
    return $returnValue
}

function Update-StorageTableRow {
    [CmdletBinding(SupportsShouldProcess)]
    # insert or update a table row: https://docs.microsoft.com/en-us/rest/api/storageservices/insert-or-replace-entity
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(Mandatory=$true)]
        [string]
        $partitionKey,

        [Parameter(Mandatory=$true)]
        [string]
        $rowKey,

        [Parameter(Mandatory=$false)]
        [hashTable]$property = @{}
    )

    # if debug is enabled, also force verbose messages
    if ($DebugPreference -ne 'SilentlyContinue') {$VerbosePreference = 'Continue'}

    Write-Verbose "Starting function Update-StorageTableRow"

    Write-Verbose ("Creating body for update request with partitionKey {0} and rowKey {1}" -f $partitionKey, $rowKey)
    $body = _createBody -partitionKey $partitionKey -rowKey $rowKey -property $property
    Write-Debug "Outputting body"
    $body | Out-String | Write-Debug

    Write-Verbose "Creating update request parameter object "
    $parameters = _createRequestParameters -table $table -method "Put" -uriPathExtension ("(PartitionKey='{0}',RowKey='{1}')" -f $partitionKey, $rowKey)

    # debug
    Write-Debug "Outputting parameter object"
    $parameters | Out-String | Write-Debug
    $parameters.headers | Out-String | Write-Debug

    if ($PSCmdlet.ShouldProcess($table.Uri.ToString(), "Update-StorageTableRow")) {
        Write-Verbose "Updating entity in storage table"
        $result = Invoke-WebRequest -Body $body @parameters

        return(_processResult -result $result)
    }
}

function Add-StorageTableRow {
    [CmdletBinding(SupportsShouldProcess)]
    # insert a table row: https://docs.microsoft.com/en-us/rest/api/storageservices/insert-entity
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(Mandatory=$true)]
        [string]
        $partitionKey,

        [Parameter(Mandatory=$true)]
        [string]
        $rowKey,

        [Parameter(Mandatory=$false)]
        [hashTable]$property = @{},

        [Switch]$returnContent
    )

    # if debug is enabled, also force verbose messages
    if ($DebugPreference -ne 'SilentlyContinue') {$VerbosePreference = 'Continue'}

    Write-Verbose "Starting function Add-StorageTableRow"

    Write-Verbose ("Creating body for insert request with partitionKey {0} and rowKey {1}" -f $partitionKey, $rowKey)
    $body = _createBody -partitionKey $partitionKey -rowKey $rowKey -property $property
    Write-Debug "Outputting body"
    $body | Out-String | Write-Debug

    Write-Verbose "Creating insert request parameter object "
    $parameters = _createRequestParameters -table $table -method "Post"

    # Add header to prevent return body, unless requested
    if (-Not $returnContent) {
        $parameters.headers.add("Prefer", "return-no-content")
    }

    # debug
    Write-Debug "Outputting parameter object"
    $parameters | Out-String | Write-Debug
    $parameters.headers | Out-String | Write-Debug

    if ($PSCmdlet.ShouldProcess($table.Uri.ToString(), "Add-StorageTableRow")) {
        Write-Verbose "Inserting entity in storage table"
        $result = Invoke-WebRequest -Body $body @parameters

        return(_processResult -result $result)
    }
}

function Remove-StorageTableRow {
    [CmdletBinding(SupportsShouldProcess)]
    # delete a table row: https://docs.microsoft.com/en-us/rest/api/storageservices/delete-entity1
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(Mandatory=$true)]
        [string]
        $partitionKey,

        [Parameter(Mandatory=$true)]
        [string]
        $rowKey
    )

    # if debug is enabled, also force verbose messages
    if ($DebugPreference -ne 'SilentlyContinue') {$VerbosePreference = 'Continue'}

    Write-Verbose "Starting function Remove-StorageTableRow"

    Write-Verbose "Creating delete request parameter object "
    $parameters = _createRequestParameters -table $table -method "Delete" -uriPathExtension ("(PartitionKey='{0}',RowKey='{1}')" -f $partitionKey, $rowKey)

    $parameters.headers.add("If-Match", "*")


    # debug
    Write-Debug "Outputting parameter object"
    $parameters | Out-String | Write-Debug
    $parameters.headers | Out-String | Write-Debug

    if ($PSCmdlet.ShouldProcess($table.Uri.ToString(), "Remove-StorageTableRow")) {
        Write-Verbose "Deleting entity in storage table"
        $result = Invoke-WebRequest @parameters

        return(_processResult -result $result)
    }
}

function Get-StorageTableNextRow {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
    [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(Mandatory=$true)]
        [string]
        $paginationQuery
    )

    # if debug is enabled, also force verbose messages
    if ($DebugPreference -ne 'SilentlyContinue') {$VerbosePreference = 'Continue'}

    Write-Verbose "Starting function Get-StorageTableNextRow"

    # recreate the original filterString in case we have more pages
    Write-Verbose "Extracting original filterString"
    $filterString = $paginationQuery -replace "&NextPartitionKey.+?(?=\&|$)", "" -replace "&NextRowKey.+?(?=\&|$)", ""
    $filterString | Out-String | Write-Debug

    # create parameter table
    Write-Verbose "Creating next page get request parameter object "
    $parameters = _createRequestParameters -table $table -method "Get" -uriPathExtension "()"
    $parameters.uri = ("{0}?{1}" -f $parameters.uri, $paginationQuery)

    # debug
    Write-Debug "Outputting parameter object"
    $parameters | Out-String | Write-Debug
    $parameters.headers | Out-String | Write-Debug

    if ($PSCmdlet.ShouldProcess($table.Uri.ToString(), "Get-StorageTableNextRow")) {
        # get the results
        Write-Verbose "Getting results in storage table"
        $result = Invoke-WebRequest @parameters

        # return
        return (_processResult -result $result -filterString $filterString)
    }
}

function Get-StorageTableRow {
    [CmdletBinding(SupportsShouldProcess)]
    # Query a table row: https://docs.microsoft.com/en-us/rest/api/storageservices/query-entities
    # Based on: https://github.com/paulomarquesc/AzureRmStorageTable/blob/master/AzureRmStorageTableCoreHelper.psm1
    param (
        [Parameter(Mandatory=$true,ParameterSetName='GetAll')]
        [Parameter(ParameterSetName='byPartitionKey')]
        [Parameter(ParameterSetName='byRowKey')]
        [Parameter(ParameterSetName="byCustomFilter")]
        [Microsoft.Azure.Cosmos.Table.CloudTable]
        $table,

        [Parameter(ParameterSetName="GetAll")]
		[Parameter(ParameterSetName="byPartitionKey")]
		[Parameter(ParameterSetName="byRowKey")]
		[Parameter(ParameterSetName="byCustomFilter")]
		[System.Collections.Generic.List[string]]$selectColumn,

        [Parameter(Mandatory=$true,ParameterSetName='byPartitionKey')]
        [Parameter(Mandatory=$true,ParameterSetName='byRowKey')]
        [string]
        $partitionKey,

        [Parameter(Mandatory=$true,ParameterSetName='byRowKey')]
        [string]
        $rowKey,

        [Parameter(Mandatory=$true, ParameterSetName="byCustomFilter")]
		[string]$customFilter,

        [Parameter(Mandatory=$false)]
		[Nullable[Int32]]$top = $null
    )

    # if debug is enabled, also force verbose messages
    if ($DebugPreference -ne 'SilentlyContinue') {$VerbosePreference = 'Continue'}

    Write-Verbose "Starting function Get-StorageTableRow"

    If ($PSCmdlet.ParameterSetName -eq "byPartitionKey"){
        [string]$filter = ("PartitionKey eq '{0}'" -f $partitionKey)
    } elseif ($PSCmdlet.ParameterSetName -eq "byRowKey"){
        [string]$filter = ("PartitionKey eq '{0}' and RowKey eq '{1}'" -f $partitionKey, $rowKey)
    } elseif ($PSCmdlet.ParameterSetName -eq "byCustomFilter"){
        [string]$filter = $customFilter
    } else {
        [string]$filter = $null
    }

    [string]$filterString = ''

    Write-Verbose "Creating filterString if needed"
    # Adding filter if not null
	if (-not [string]::IsNullOrEmpty($Filter))
	{
		[string]$filterString += ("`$filter={0}"-f $Filter)
	}

    # Adding selectColumn if not null
	if (-not [string]::IsNullOrEmpty($selectColumn))
	{
        if ($filterString) {$filterString+='&'}
		[string]$filterString = ("{0}`$select={1}"-f $filterString, ($selectColumn -join ','))
	}

    # Adding top if not null
	if ($null -ne $top)
	{
        if ($filterString) {$filterString+='&'}
		[string]$filterString = ("{0}`$top={1}"-f $filterString, $top)
	}

    Write-Debug "Output filterString"
    $filterString | Out-String | Write-Debug

    # build the default parameter table
    Write-Verbose "Creating get request parameter object "
    $parameters = _createRequestParameters -table $table -method 'Get' -uriPathExtension "()"
    if ($filterString){
        $parameters.uri = ("{0}?{1}" -f $parameters.uri, $filterString)
    }
    
    # debug
    Write-Debug "Outputting parameter object"
    $parameters | Out-String | Write-Debug
    $parameters.headers | Out-String | Write-Debug
    
    if ($PSCmdlet.ShouldProcess($table.Uri.ToString(), "Get-StorageTableRow")) {
        # get the results
        Write-Verbose "Getting results in storage table"
        $result = Invoke-WebRequest @parameters

        # return
        return (_processResult -result $result -filterString $filterString)
    }
}