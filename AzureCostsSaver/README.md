# Costs saver for Azure

This task will take Azure Resource group name as an input and use Azure Powershell runner in VSTS to get all Azure web apps, SQL databases and Virtual machines in this resource group.

If user selects to Downscale costs - web apps are scaled to B1 size, SQL databases to S0, VMs - deprovisioned. Web app and SQL database sizes are saved in 

If Downscale parameter is set to $False - then script will read tags and restore

## Issues

1. Script will silently fail if you try to run upscaling before downscaling

1. Script will fail if Tags are missing

1. There is no way for web apps to be downscaled to Basic, as at this point of time I could not check, if there is a staging slot on web app present (Basic does not allow slots at all)

## Use case

Downscale Azure resources for Testing and Acceptance environments during nights and weekends to save on costs.
