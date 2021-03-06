# Aeon ArchivesSpace Import Addon

## Version
- 1.0.1

## Workflow

For each request in the queue defined by *RequestMonitorQueue*, the server addon will use the ArchivesSpace API top_containers endpoint to import the \_resolved.title of the first current container_location retrieved to the Aeon field defined by *LocationDestinationField* and the request will be routed to *SuccessRouteQueue*. The method used to do this depends on the addon's configuration. If *TopContainerUriField* is not blank, the addon can retrieve the location with that field alone. If *RepoCodeField* is not blank, the Aeon field defined by *RepoCodeField* is used to first get a list of ArchivesSpace repos by repo_code. The repo ID is then retrieved from the repo with a matching repo_code, and the repo ID and barcode in the Aeon field defined by *BarcodeField* are used to retrieve the location. If *RepoIdMapping* is not blank, the mapping is first resolved and the repo ID selected based on the Aeon Site field. The repo ID and barcode defined by *BarcodeField* are then used to retrieve the location. If more than one of these settings contains a value, *TopContainerUriField* is prioritized, followed by *RepoCodeField*, and finally *RepoCodeMapping*. Requests will be routed to the *ErrorRouteQueue* in the following cases:
* The addon fails to connect to the ArchivesSpace API
* The ArchivesSpace API request is invalid
* The ARchivesSpace API request returns a Not Found (404)

## Installation
This addon requires two Lua libraries that are included in the distribution.

*    Atlas Helpers
*    Atlas JSON Parser
*    Atlas Tag Processor

## Addon Settings

### **RequestMonitorQueue (string)**
The queue that the addon will monitor for transactions that need ArchivesSpace data automatically imported. Required. Default: ArchivesSpace Data Import

### **SuccessRouteQueue (string)**
The queue that the addon will route requests to after successfully importing data from ArchivesSpace. Required. Default: New Request

### **ErrorRouteQueue (string)**
The queue that the addon will route requests to if erros are encountered while importing data from ArchivesSpace. Required. Default: ArchivesSpace Data Needed

### **ArchivesSpaceApiUrl (string)**
URL of the ArchivesSpace API. Required.

### **ArchivesSpaceUsername (string)**
Staff username for Aeon user to access API. Required.

### **ArchivesSpacePassword (string)**
Staff password for Aeon user to access API. Required.

### **TopContainerUriField (string)**
Specifies the custom transaction field that contains the ArchivesSpace record's top container URI. Leave blank to search for the record by repo ID and barcode. If used the value of this setting must match the name of a column from the Transactions custom fields table. Default: TopContainerID

### **RepoCodeField (string)**
Specifies the Aeon field that contains the ArchivesSpace repo_code. Leave blank to use TopContainerUriField or RepoIdMapping. Must be a tag. Ex: {TableField:Transaction.ItemInfo1}

### **RepoIdMapping (string)**
A comma-separated list of repo IDs and corresponding Aeon site codes. Leave blank to use TopContainerUriField or RepoCodeField. Ex: 123=SITE1,456=SITE2,789=SITE3 
Repo IDs can be found as part of the URL when browsing repositories or collections in ArchivesSpace. The ID will be the number following "repositories/" in the URL. For example, in https://yourarchivesspace.com//repositories/3/resources/1, the Repo ID is 3. If our URLs do not follow this format, you can log into the ArchivesSpace staff interface and view the source of any page with a "Select Repository" dropdown. Search for a select input with the ID "id."

```
<select name="id" id="id" class="form-control"><option selected="selected" value="2">CAT</option>
    <option value="3">Special Collections</option>
    <option value="4">SANDBOX</option>
    <option value="5">The Vault</option>
</select>
```
The option values are the repo IDs.

### **BarcodeField (string)**
Specifies the Aeon field that contains the ArchivesSpace barcode. Required when using RepoCodeField or RepoIdMapping. Must be a tag. Ex: {TableField:Transaction.ItemInfo2}

### **LocationDestinationField (string)**
Specifies the transaction field where the location information for the transaction should be stored. The value of this setting must match the name of a column from the Transactions table. Default: Location