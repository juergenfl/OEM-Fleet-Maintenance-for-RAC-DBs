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
So the first if/then block is containing the pre-actions where the if/else block contains the post-actions. In each block, we are checking for the name of the FM operation which is stored in parameter ´$MAINTENANCE_PURPOSE` and call for the given operation the listed procedures. The first procedure is always named like `setup_env_...` and is there to set parameter like
```
OLD_GI_HOME
NEW_GI_HOME
OLD_DB_HOME
NEW_DB_HOME
```
depending on the performed operation. These parameters can be used then in the other procedures to perform the needed action.

To add more actions, just define the needed procedures and call them in the pre- or post-action block for the right operation, that's all.

The script is run as non-privileged user, since we would not be able to run scripts as user root on the other nodes as well.

If certain commands must be run at root, they can be appended to the script `$ROOT_SH` and comments for running it can be written to `stdout` so that they will get catched in the job logs.
You can use the procedure `check_olr_loc_config()` as a reference for this.

For each performed operation you will find on each cluster node a directory contain the used script, the inputfile and the trace of the run form the script which will include error messages as well, if there has been such. From the job log:
```
.....
All files from this run can be found here: /u01/app/oracle/FM-pre-post-actions/UPDATE_GI_27720
.....
```
Content of `UPDATE_GI_27720`:
```
$ ls -l /u01/app/oracle/FM-pre-post-actions/UPDATE_GI_27720
total 44
-rwxr-xr-x. 1 oracle oinstall 35191 Mar 18 20:10 action_script.sh
-rw-r-----. 1 oracle oinstall  1113 Mar 18 20:10 inputfile.txt
-rw-r--r--. 1 oracle oinstall  3206 Mar 18 20:10 logfile.trc

$ cat /u01/app/oracle/FM-pre-post-actions/UPDATE_GI_27720/logfile.trc
.....
[ 938 ] false
[ 968 ] echo 'Performing UPDATE_GI post-patch actions'
[ 971 ] init_root_sh
[ 165 ] ROOT_SH=/u01/app/oracle/FM-pre-post-actions/root.sh
[ 168 ] '[' -f /u01/app/oracle/FM-pre-post-actions/root.sh ']'
[ 192 ] echo '#!/bin/bash'
[ 199 ] chmod 755 /u01/app/oracle/FM-pre-post-actions/root.sh
[ 973 ] case "$MAINTENANCE_PURPOSE" in
[ 975 ] MAINTENANCE_PURPOSE=UPDATE_GI
[ 976 ] setup_env_UPDATE_ROLLBACK_GI
[ 238 ] echo 'Setting up environment'
[ 241 ] OLD_GI_HOME=/u01/app/gi/19.15.0.0
[ 242 ] NEW_GI_HOME=/u01/app/gi/19.21.0.0
[ 243 ] echo 'OLD_GI_HOME = /u01/app/gi/19.15.0.0'
[ 244 ] echo 'NEW_GI_HOME = /u01/app/gi/19.21.0.0'
[ 245 ] echo
[[ 252 ] crsctl stat res -t
[[ 252 ] grep '^ora\..*\.db$'
[[ 252 ] head -1
[ 252 ] DB_SERVICE_NAME=ora.jfrac122.db
[[ 253 ] crsctl stat res ora.jfrac122.db -p
[[ 253 ] grep '^ORACLE_HOME='
[[ 253 ] cut -d= -f2
[ 253 ] DB_HOME=/u02/app/oracle/product/19.15.0.0/dbhome_1
.....
```

The tracefile `logfile.trc` will be helpful when troubleshooting issues with your procedures.
