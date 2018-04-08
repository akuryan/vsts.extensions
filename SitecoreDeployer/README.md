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

    1. MsDeploy - will deploy vaniall Sitecore with database

    1. Redeploy - will deploy vanilla Sitecore without databases

```Generate SAS``` - if set to ```True```, then, if your scwdp packages are located on storage account at same subscription, then powershell will generate short-time SAS signatures for them.

```License``` - insert here you license.xml content / file path / link to license.xml file (if stored on storage account in same subscription and ```Generate SAS``` is set to ```True```, then it will be downloaded with freshly generated SAS)