# Oracle Enterprise Manager (OEM) Fleet Maintenance for Real Application Cluster Databases (RAC DBs)

[OEM Fleet Maintenance](https://docs.oracle.com/en/enterprise-manager/cloud-control/enterprise-manager-cloud-control/13.5/emlcm/database-fleet-maintenance.html#GUID-60B39D16-322B-435F-85F0-C39AFC80E96B) is part of the [Oracle Enterprise Manager Database Lifecycle Management Pack](https://www.oracle.com/manageability/enterprise-manager/technologies/database-lifecycle-management-pack.html), which meets all lifecycle management challenges easily by automating time-consuming tasks related to discovery, initial provisioning, cloning, patching, configuration management, ongoing change management, and compliance management.

Fleet Maintenance (FM) focuses on procedures to standardize database environments by automatically patching and upgrading a large number of databases without application downtime for RAC databases. FM includes [pre and post actions](https://docs.oracle.com/en/enterprise-manager/cloud-control/enterprise-manager-cloud-control/13.5/emlcm/custom-and-scripts-fleet-operations.html) to handle custom configuration changes not adressed by out-of-the-box FM procedures. Clustered environments such as RAC database present unique challenges for patching and upgrading. This is because some configuration changes needs to be applied on all cluster nodes, while others require applying to ethier the first node or the last node. Careful coordination is needed to address these dependancies before patching a RAC Cluster.
  
The concept of Fleet Maintenance custom pre and post action scripts for RAC DBs are designed to run on one cluster node. The scripts will contain the logic to determine which nodes it will need to run on.

This repository contains a sample pre and post action script for RAC environments which contains the needed logic and provides a framework which can easily be configured to add any further custom changes during RAC patching.

The script can be found in the [script](./script/) folder, and documentation can be found [docs](./docs/) folder.

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, see [CONTRIBUTING](./CONTRIBUTING.md) for details.

## License

Copyright (c) 2021, 2024 Oracle and/or its affiliates.
Released under the Universal Permissive License (UPL), Version 1.0.
See [LICENSE](./LICENSE) for more details.

