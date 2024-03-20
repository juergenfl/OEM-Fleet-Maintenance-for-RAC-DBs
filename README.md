# Oracle Enterprise Manager (OEM) Fleet Maintenance for Real Application Cluster Databases (RAC DBs)

[OEM Fleet Maintenance](https://docs.oracle.com/en/enterprise-manager/cloud-control/enterprise-manager-cloud-control/13.5/emlcm/database-fleet-maintenance.html#GUID-60B39D16-322B-435F-85F0-C39AFC80E96B) is part of the [Oracle Enterprise Manager Database Lifecycle Management Pack](https://www.oracle.com/manageability/enterprise-manager/technologies/database-lifecycle-management-pack.html), which allows to fully help you meet all lifecycle management challenges easily by automating time-consuming tasks related to discovery, initial provisioning and cloning, patching, configuration management, ongoing change management, and compliance management.

Fleet Maintenance (FM) focuses on procedures to standardize database environments by automatically patching and upgrading a large number of databases e.g. with no application downtime at all for RAC databases. FM allows 
to include [pre and post actions](https://docs.oracle.com/en/enterprise-manager/cloud-control/enterprise-manager-cloud-control/13.5/emlcm/database-fleet-maintenance.html#GUID-44E212D9-774A-409E-AEFC-C20458FA767F) to handle required custom config changes not adressed by the out-of-the-box FM procedures. Clustered environments like a RAC DB are a special challenge for patching and upgrading since some config changes needs to be applied on all cluster nodes, others on the first node patched or on the last node patched. This all can be needed before the actual RAC or DB patching starts or when patching is done.
  
The concept of FM custom pre and post action scripts for RAC DBs therefore is the following: The pre and post action scripts will be called only on one cluster node and the scripts itselves must contain the logic to determine on which nodes it needs to get run.

This repository contains a sample pre and post action script for RAC environments which contains the needed logic and provides a framework which allows to add any further needed custom changes during RAC patching.

The actual script can be found in the [script](./script/) folder, the documentation for it in the [docs](./docs/) folder.

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, see [CONTRIBUTING](./CONTRIBUTING.md) for details.

## License

Copyright (c) 2021, 2024 Oracle and/or its affiliates.
Released under the Universal Permissive License (UPL), Version 1.0.
See [LICENSE](./LICENSE) for more details.

