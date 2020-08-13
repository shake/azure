# Step 1: Input parameters  
param([String]$EnvironmentName = "ABB30",`
      [String]$Stage = "Dev",`
      [String]$Location = "westeurope"`
      )
$OutputFormat = "table"  # other options: json | jsonc | yaml | tsv
# internal: assign resource names
$ResourceGroupName = "RG-$EnvironmentName-$Stage"
$ADFName = "ADF-$EnvironmentName-$Stage"
$KeyVaultName ="KV-$EnvironmentName-$Stage"
$StorageName = "adls$EnvironmentName$Stage".ToLower().Replace("-","")
Get-Variable ResourceGroupName, ADFName, KeyVaultName, StorageName | Format-Table 



# Step 2: Create a Resource Group
if (-Not (az group list --query "[].{Name:name}" -o table).Contains($ResourceGroupName))
{
    "Create a new resource group: $ResourceGroupName" 
    az group create --name $ResourceGroupName --location $Location --output $OutputFormat
}`
else 
{
   "Resource Group: $ResourceGroupName already exists"
}


# Step 3a: Create a Key Vault
if (-Not (az keyvault list --resource-group $ResourceGroupName ` --query "[].{Name:name}" -o table).Contains($KeyVaultName))
{
    Write-Host "Creating a new key vault account: $KeyVaultName"
    az keyvault create `
       --location $Location `
       --name $KeyVaultName `
       --resource-group $ResourceGroupName `
       --output $OutputFormat    
}`
else
{
    "Key Vault: Resource $KeyVaultName already exists"
}


# Step 3b: Create a Storage Account
if (-Not (az storage account list --resource-group $ResourceGroupName --query "[].{Name:name}" -o table).Contains($StorageName))
{
       Write-Host "Creating a new storage account: $StorageName"
       
       az storage account create `
       --name $StorageName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku "Standard_LRS" `
        --kind "StorageV2" `
        --enable-hierarchical-namespace $true  `
        --output $OutputFormat      
}`
else
{
    "Storage: Account $StorageName already exists"
}


# Step 4: Create a Data Factory
az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file "./adf.json" `
  --parameters name=$ADFName location=$Location `
  --output $OutputFormat
  
  


# Configuring a storage account:

"#Step 5.1: Obtaining a connection string and storage account key"
$connectionString= (az storage account show-connection-string `
                                -n $StorageName `
                                -g $ResourceGroupName `
                                --query connectionString `
                                -o tsv `
                    )
$StorageKey=(az storage account keys list -g $ResourceGroupName `
                                -n $StorageName `
                                --query [0].value -o tsv `
            )


"#Step 5.2: Creating a container `dwh` "
az storage container create `
            --name "dwh" `
            --public-access off `
            --connection-string $connectionString `
            --output $OutputFormat

"#Step 5.3: uploading a sample file to a container"
az storage blob upload `
    --name "MoviesDB.csv" `
    --container "dwh" `
    --file "moviesDB.csv" `
    --connection-string $connectionString `
    --no-progress `
    --output $OutputFormat

# Adding a secret to a Key Vault

"#Step 6.1: Adding a storage account connection string to a key vault"
az keyvault secret set `
            --vault-name $KeyVaultName `
            --name "AzStorageKey" `
            --value $StorageKey `
            --output none

"#Step 6.2: Obtaining an Object ID of Azure Data Factory instance"
$ADF_Object_ID =  (az ad sp list `
                        --display-name $ADFName `
                        --output tsv `
                        --query "[].{id:objectId}" `
                   )

"#Step 6.3: Granting access permissions of ADF to a KeyVault"
az keyvault set-policy `
            --name $KeyVaultName `
            --object-id $ADF_Object_ID `
            --secret-permissions get list `
            --query "{Status:properties.provisioningState}" `
            --output $OutputFormat

