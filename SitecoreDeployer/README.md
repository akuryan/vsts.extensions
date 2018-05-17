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

    1. Deploy - will deploy vanilla Sitecore without databases

```Generate SAS``` - if set to ```True```, then, if your scwdp packages are located on storage account at same subscription, then powershell will generate short-time SAS signatures for them.

```License location``` - insert here you license.xml content / file path / link to license.xml file (if stored on storage account in same subscription and ```Generate SAS``` is set to ```True```, then it will be downloaded with freshly generated SAS)

### Security section

Allows to limit access to PRC and REP roles as advised at [Sitecore documentation](https://doc.sitecore.net/sitecore_experience_platform/setting_up_and_maintaining/sitecore_on_azure/analytics/securing_microsoft_azure_resources_for_a_sitecore_deployment). I suppose that CM instance IP-based limitation is set in web.config of application - so, it is not added in this extension.

I shall note, that inputs are not validated strictly, so - it will try to write whatever you specify to restrictions

```Limit access to PRC role by IP``` - if selected (true by default) it allows to define IP-based restriction (by default, all IP's are denied access to PRC instance). If you are already deploying something to web app, and you do have ipRestriction set in your web.config - disable this checkbox, because current scwdp packages, shipped by Sitecore do not allow neither multiple IP addresses defined in template, nor multiple ip addresses defined on web app level for PRC role. This checkbox shall be disabled if you are not deploying CM instance web.config and relying on default Sitecore web.config for CM instance (because both CM and PRC instances share one setting for allowing *one, and only one* IP address). IP Restriction will be still written on web app level (so, if you are deploying own web.config - you'll be safe and would not need to keep in mind fact that you need to protect this web app as well).

```Limit access to REP role by IP``` - if selected (true by default) it allows to define IP-based restriction (Sitecore recommends to allow only Azure IPs, but I narrow it here to outbound IPs of Azure Web apps in our resource group). If you are already deploying something to web app, and you do have ipRestriction set in your web.config - do not use this section, as it _could_ conflict with existing set of rules (for example, duplicate IP specified) or be completely ineffective, if ```<ipSecurity>``` section starts with ```<clear />``` statement (it is cleared then :) )

```Limit access to CM role by IP``` - if selected (false by default) will allow all outgoing IPs of all web apps in current resource group to access CM instance. Also, will take input from ```IP/Mask comma-separated collection``` as well. Could be combined with ```<ipSecurity>``` section in your web.config - just do not forget to omit ```<clear />``` directive, then

```IP/Mask comma-separated collection``` - comma-separated collection of IP/Mask pairs to be set for REP instance access allow list.