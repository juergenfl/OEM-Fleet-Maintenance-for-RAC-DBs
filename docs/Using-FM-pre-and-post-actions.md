# How to use Custom Pre and Post Scripts for Fleet Maintenance Operations

## Introduction

In order to support automated maintenance activities for different Fleet Maintenance (FM) operations, Oracle Enterprise Manager allows support for configuring custom Pre/Post scripts for different operations. There pre/post scripts need to be uploaded as EM Software Library Entity(Directive) prior to their usage with FM operations. All details can be found [here](https://docs.oracle.com/en/enterprise-manager/cloud-control/enterprise-manager-cloud-control/13.5/emlcm/database-fleet-maintenance.html#GUID-6AF19CA9-E83A-4C76-BF50-16E5A072EF92) in the documentation.

## Getting started with the provided script

The bash script [FM_pre-post-actions.sh](../script/FM_pre-post-actions.sh) can be seen as kind of reference implementation for Pre-/Post-actionscripts for RAC DB environments. I did create it a while ago for a customer environment with several special customizations very likely due to historical workarounds still needed by existing applications or scripts.

Here is an example:

The <samp>listener.ora</samp> file actually used on RAC nodes is the one located at <samp>\$GI_HOME/network/admin/listener.ora</samp>. Let's assume that there are still DB related scripts in use which expects the <samp>listener.ora</samp> file at <samp>\$DB_HOME/network/admin/listener.ora</samp>. The established workaround has been to have a symbolic link <samp>\$DB_HOME/network/admin/listener.ora -> \$GI_HOME/network/admin/listener.ora</samp> in place for this purpose.

Since <samp>GI_HOME</samp> and <samp>DB_HOME</samp> get updated independently by different FM operations, an <samp>UPDATE_GI</samp> post action would need to update the symbolic link in <samp>\$DB_HOME/network/admin/</samp> since this is completely out of scope for the generic <samp>UPDATE_GI</samp> procedures. The same of course for a possible <samp>ROLLBACK_GI</samp> operation.
