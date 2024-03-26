Structure of the script and how to add your own needed procedures to it

# Structure of the script
To get an understanding of the structure of the script, let me recap the constrains we have for FM operations in RAC environments
 * during a given operation like `UPDATE_GI`, the pre and post action scripts/directives will be called only on one cluster node
 * you cannot rely on which node will get picked for running the script
 * by default, a single argument will get passed to the script which is the path to a file containing all available input values. You can modify this when creating the directive but I have used the default settings

Here are the initial steps performed when the script gets called by the FM framework:
 1. The script detects that an argument got passed to it, therefore it got called by the FM framework
 2. It will call the cluster framework to get a list of all nodes
 3. It will copy itself and the inputfile to each cluster node
 4. It will run the script on all other cluster nodes remotely without an argument passed
 5. It will finally continue to run on the initial cluster node knowing that it is the last node

The main part of the script is now the following:
```
###################################################################
#
# main part of action script
#
###################################################################

if $PREPATCH; then
    echo "Performing $MAINTENANCE_PURPOSE pre-patch actions"
    case "$MAINTENANCE_PURPOSE" in
    UPDATE_GI|PS_UPDATE_GI)
	MAINTENANCE_PURPOSE=UPDATE_GI
        setup_env_UPDATE_ROLLBACK_GI
        check_listener_ora
        ;;
    ROLLBACK_GI|PS_ROLLBACK_GI)
	MAINTENANCE_PURPOSE=ROLLBACK_GI
        setup_env_UPDATE_ROLLBACK_GI
        check_listener_ora
        copy_tnsnames_ora_to_original_GI_HOME
        ;;
    UPDATE_RACDB)
        setup_env_UPDATE_RACDB
        stop_backup_vip_service
        check_tnsnames_ora
        ;;
    ROLLBACK_RACDB)
        setup_env_ROLLBACK_RACDB_prepatch
        stop_backup_vip_service
        check_tnsnames_ora
        ;;
    *)
       echo "MAINTENANCE_PURPOSE = $MAINTENANCE_PURPOSE"
       echo "nothing to do ..."
       ;;
    esac
else
    echo "Performing $MAINTENANCE_PURPOSE post-patch actions"

    # there is no need to create root.sh in prepatch step, only postpatch
    init_root_sh
    
    case "$MAINTENANCE_PURPOSE" in
    UPDATE_GI|PS_UPDATE_GI)
	MAINTENANCE_PURPOSE=UPDATE_GI
        setup_env_UPDATE_ROLLBACK_GI
        check_tfa_config
        check_listener_ora_postpatch
        ;;
    ROLLBACK_GI|PS_ROLLBACK_GI)
	MAINTENANCE_PURPOSE=ROLLBACK_GI
        setup_env_UPDATE_ROLLBACK_GI
        check_tfa_config
        check_listener_ora_postpatch
        check_olr_loc_config
        ;;
    UPDATE_RACDB)
        setup_env_UPDATE_RACDB
        start_backup_vip_service
        check_tnsnames_ora_postpatch
        check_listener_ora_postpatch
        check_pathes_in_listener_ora
        ;;
    ROLLBACK_RACDB)
        setup_env_ROLLBACK_RACDB_postpatch
        start_backup_vip_service
        check_tnsnames_ora_postpatch
        check_listener_ora_postpatch
        check_pathes_in_listener_ora
        ;;
    *)
       echo "MAINTENANCE_PURPOSE = $MAINTENANCE_PURPOSE"
       echo "nothing to do ..."
       ;;
    esac

    finalize_root_sh

fi

echo "done with all actions on node $(hostname)"
```
