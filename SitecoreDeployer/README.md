# Sitecore Deployer for VSTS

This release task is based on our mutual work with [Rob Habraken](https://github.com/robhabraken) on [Sitecore deployment script for Azure](https://github.com/robhabraken/Sitecore-Azure-Scripts/tree/master/Scripts/00%20Functions)

This extension will deploy Sitecore in Azure basing on ARM templates, developed by Rob and inherited from Sitecore.

## Usage

Select your Azure Connection Type (normally, it shall be ```Azure Resource Manager```) - this shall be preconfigured on your VSTS instance.

Select your Azure subscription in which Sitecore resources shall be deployed in field ```Azure RM Subscription```

```ARM template path``` - provide path to ARM template

```ARM parameters path``` - provide path ARM parameters file

```Resource group name``` - provide name of resource group

```Location``` - select Azure data center location

```Deployment type``` - select [Sitecore deployment type](https://www.robhabraken.nl/index.php/2740/blue-green-sitecore-deployments-on-azure/):

    1. Infra - will deploy infrastructure only

    1. Deploy - will try to get parameters from "sitecore-infra" deployment on resource group and add them to deployment parameters (so, this mode shall be used if you have had an infra deployment before)

```Generate SAS``` - if set to ```True```, then, if your scwdp packages are located on storage account at same subscription, then powershell will generate short-time SAS signatures for them.

```License location``` - insert here you license.xml content / file path / link to license.xml file (if stored on storage account in same subscription and ```Generate SAS``` is set to ```True```, then it will be downloaded with freshly generated SAS)

```Additional ARM parameters``` - allows to pass additional or override existing parameters to ARM templates. This string shall be passed in ```-name value``` format, use grid editor for changing this. Example: ```-sas ?st=2018-05-28&test=test -url test```. Use case for this: usage of nested templates, which requires that templates are being accessed only via HTTP(S) (Sitecore 9 deployments, for example): when storing templates at closed source control repository, not accessible from the wild Internet, you could push them to blob storage in folder with release number (achieving versioning), generate a link and pass it along with short living SAS to a task in parameters. Previous format with ```name=value``` format, several parameters shall be separated by line end symbol ``` \n ```(do not forget about space symbol before and after). Example: ```sas=?st=2018-05-28&test=test \n url=test``` is supported, if entered manually (or when upgrading version), but usage is discouraged, as there is no supproted editor for it.

### Template parameters at KeyVault

If you wish too - you can store template parameters sensitive values in Azure KeyVault - this allows better security and (if you wish too) shared responsibilities: developers do not necessary need to know Sitecore admin password, for example... To reach this, one shall replace regular parameter definition, which looks like this:

```
  "sqlServerPassword": {"value": "someValueHere"}
```

with Azure KeyVault reference:

```
  "sqlServerPassword": {
    "reference": {
      "keyVault": {
          "id":"KeyVaultNameHere"
      },
      "secretName": "secretNameHere"
    }
  }
```

Do not forget that your build server user (or service principle) have to be able to get secrets from Azure KeyVault.

### Nested templates

Since nested templates requires that templates are residing on URI, accessible to build machine at deployment time for reading - one will need to upload them on storage account and use ```Additional ARM parameters``` field. This use case was raised in [issue #2](https://github.com/akuryan/vsts.extensions/issues/2). For now, this could be fixed in following way:

- Add one more task to my release: ```Azure File Copy``` before Sitecore deployer to upload templates to Azure Storage container. This task will upload templates to Azure Storage container in blob folder, which could be defined in variable ```$(blobPrefix)``` (```blobPrefix``` is equal to ```$(Release.ReleaseId)/$(Release.EnvironmentName)``` which allows to have separate templates for separate environments and releases). Task will output SAS and Storage container URI in variables ```storageUri``` and ```storageSas```
![1](https://user-images.githubusercontent.com/1794306/42159309-fb8a288e-7dfb-11e8-9e69-ce298ef238db.png)

- In Sitecore Deploy task in field ```Additional ARM parameters``` define following string ```-templateLinkBase $(storageUri)/$(blobPrefix)/ -templateLinkAccessToken=$(storageSas)```. You could 
This allows to inject URL for storage account and it's SAS, so, template starts deploying from local disk, but will get nested templates from Azure Storage account (actually, this is ARM limitation: you could not use nested templates from local disk - they shall be always located on URI, **accessible to host, which is executing script**, _hence, this upload to Azure Storage task addition_)

Actually, if you are not modifying nested templates (mine modifications included HTTP/2, TLS 1.2 and some other stuff, required for our application work) - you can change templateLinkBase variable to GitHub URL, pointing it to Sitecore Azure QuickStart templates

### Security section

Allows to limit access to PRC and REP roles as advised at [Sitecore documentation](https://doc.sitecore.net/sitecore_experience_platform/setting_up_and_maintaining/sitecore_on_azure/analytics/securing_microsoft_azure_resources_for_a_sitecore_deployment). I suppose that CM instance IP-based limitation is set in web.config of application - so, it is not added in this extension.

I shall note, that inputs are not validated strictly, so - it will try to write whatever you specify to restrictions

```Limit access to PRC role by IP``` - if selected (true by default) it allows to define IP-based restriction (by default, all IP's are denied access to PRC instance). If you are already deploying something to web app, and you do have ipRestriction set in your web.config - disable this checkbox, because current scwdp packages, shipped by Sitecore do not allow neither multiple IP addresses defined in template, nor multiple ip addresses defined on web app level for PRC role. This checkbox shall be disabled if you are not deploying CM instance web.config and relying on default Sitecore web.config for CM instance (because both CM and PRC instances share one setting for allowing *one, and only one* IP address). IP Restriction will be still written on web app level (so, if you are deploying own web.config - you'll be safe and would not need to keep in mind fact that you need to protect this web app as well).

```Limit access to REP role by IP``` - if selected (true by default) it allows to define IP-based restriction (Sitecore recommends to allow only Azure IPs, but I narrow it here to outbound IPs of Azure Web apps in our resource group). If you are already deploying something to web app, and you do have ipRestriction set in your web.config - do not use this section, as it _could_ conflict with existing set of rules (for example, duplicate IP specified) or be completely ineffective, if ```<ipSecurity>``` section starts with ```<clear />``` statement (it is cleared then :) )

```Limit access to CM role by IP``` - if selected (false by default) will allow all outgoing IPs of all web apps in current resource group to access CM instance. Also, will take input from ```IP/Mask comma-separated collection``` as well. Could be combined with ```<ipSecurity>``` section in your web.config - just do not forget to omit ```<clear />``` directive, then

```IP/Mask comma-separated collection``` - comma-separated collection of IP/Mask pairs to be set for REP instance access allow list.