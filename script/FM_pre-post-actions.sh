#!/bin/bash
#
# Custom Action script to be used with OEM Fleet Maintenance for RAC DBs
#
# Version: 1.5 2024-03-14 - juergen.fleischer@oracle.com
#
# 
# This script will be used as pre-patch and post-patch script:
#  - create two copies of this file, e.g. FM_prepatch_script.sh and FM_postpatch_script.sh
#  - set parameter PREPATCH to true in FM_prepatch_script.sh and to false in FM_postpatch_script.sh
#  - upload the two scripts into the SW Library
#
PREPATCH=true

#
# The restart of ohasd.bin process is required after performing a ROLLBACK_GI job due to CRS bug 30007337
#
# The postpatch script in a ROLLBACK_GI job will add the required steps to the 'root.sh' script which
# needs to be run as root after the job has finished.
#
# The actual restart of ohasd.bin can be done by a full restart of CRS or by sending a hangup signal to the ohasd.bin process.
#
# Parameter PERFORM_FULL_CRS_RESTART_IN_ROOT_SH can be used to determine the desired behavior.
#
# PERFORM_FULL_CRS_RESTART_IN_ROOT_SH=true/false
#
# true:  'crsctl stop crs -f' followed by 'crsctl start crs -wait'
#        IMPORTANT: It must be ensured that the 'root.sh' script will never get run in parallel on the cluster nodes!
# 
# false: send ohasd.bin process a HANGUP signal causing a controlled restart of CRS processes
#
PERFORM_FULL_CRS_RESTART_IN_ROOT_SH=false

# main home directory for all Fleet Maintenance custom actions (adjust to your prefered temporary location)
SCRIPT_DIR=/u01/app/oracle/FM-pre-post-actions

#######################################################################################################

# 
# OEM Fleet Maintenance is running the script only on one node
#
# The script will copy itself over to a wellknown place on both nodes and call
# this script then on both nodes 

# script and input filenames
SCRIPT_NAME=$SCRIPT_DIR/action_script.sh
INPUT_FILE=$SCRIPT_DIR/inputfile.txt

# add GI_HOME/bin to path
GI_HOME=$(ps -ef | grep '/bin/crsd.bin' | egrep -v ' grep | sed ' | sed 's@.* /@/@;s@/bin/crsd.bin.*$@@')
        
if [ -z "$GI_HOME" ]; then
        echo "ERROR: CRS daemon is not running!"
        exit 1
fi
export PATH=$GI_HOME/bin:/usr/sbin:/usr/bin:/usr/local/bin

# to ensure that certain crsctl/srvctl commands will get run only from one node
# only on the local node, we will set it to 'true' further down
THIS_IS_LAST_NODE=false

# the next part will be skipped when we run the same script on the remote node(s)
if [ $# -eq 1 ]; then
        # this is the initial state where this script gets run by the 
        # EM Agent with the path to the inputfile as argument
        #
        # we will call the same script on the other RAC nodes, but without passing the inputfile as parameter
        # this will ensure that this part will only get run on the local node

        FM_PROVIDED_INPUT_FILE="$1"

        if [ ! -f "$FM_PROVIDED_INPUT_FILE" ]; then
                echo "ERROR: Inputfile $FM_PROVIDED_INPUT_FILE not found!"
                exit 1
        fi
    
        THIS_NODE=$(hostname --short)

        REMOTE_NODES=$(olsnodes | grep -v $THIS_NODE)

        for NODE_NAME in $REMOTE_NODES
        do
                # echo "Creating directory $SCRIPT_DIR on node $NODE_NAME"
                ssh -o StrictHostKeyChecking=no $NODE_NAME "mkdir -p $SCRIPT_DIR"

                # echo "Copying action script to node $NODE_NAME. Scriptname: $SCRIPT_NAME"
                scp -q -o StrictHostKeyChecking=no $0 ${NODE_NAME}:$SCRIPT_NAME
                ssh -o StrictHostKeyChecking=no $NODE_NAME "chmod 755 $SCRIPT_NAME"

                # echo "Copying inputfile to node $NODE_NAME. Filename: $INPUT_FILE"
                scp -q -o StrictHostKeyChecking=no $FM_PROVIDED_INPUT_FILE ${NODE_NAME}:$INPUT_FILE
                
                # echo "Running script on node $NODE_NAME"
                ssh -o StrictHostKeyChecking=no $NODE_NAME $SCRIPT_NAME
        done

        # preparing local node
        mkdir -p $SCRIPT_DIR
        /usr/bin/cp $0 $SCRIPT_NAME
        /usr/bin/cp $FM_PROVIDED_INPUT_FILE $INPUT_FILE

        # see above, this will enable the check/fix script to contain parts which should get run only on one node
        # an example is stopping/starting of cluster services/resources in pre-/postpatch scripts
        THIS_IS_LAST_NODE=true

fi


################################################################
#
# Preparing run directory and script tracing
#
###############################################################y

echo
echo "Running script on node $(hostname)"

# sourcing input_file
. $INPUT_FILE 2>/dev/null

# note: when sourcing inputfile, there will be an error due to this parameter definition:
# 
# ORACLE_HOME_TARGET_DETAILS=stdbyrac-2.localdomain:OraGI12Home1_1_stdbyrac-2.localdomain_7105;stdbyrac-1.localdomain:OraGI12Home1_1_stdbyrac-1.localdomain_7105;
#
# we are using ';' to separate OHs, but this will cause the 2nd OH being interpreted as command
#

# creating RUN_DIRECTORY
RUN_DIRECTORY=$SCRIPT_DIR/${MAINTENANCE_PURPOSE}_$$
mkdir -p $RUN_DIRECTORY
echo "All files from this run can be found here: $RUN_DIRECTORY"

# saving script and inputfile in RUN_DIRECTORY
cp $SCRIPT_NAME $RUN_DIRECTORY
cp $INPUT_FILE $RUN_DIRECTORY

# tracefile of script
TRACE_FILE=$RUN_DIRECTORY/logfile.trc

# capturing environment parameters in tracefile
echo 'Environment Parameters:'         >$TRACE_FILE
env                                    >>$TRACE_FILE
echo '-----------------------'         >>$TRACE_FILE
echo                                   >>$TRACE_FILE

# start script tracing
export PS4="[ \$LINENO ] "
exec 2>>$TRACE_FILE
set -x

###################################################################
#
# actual Action Script starts here
#
###################################################################

###################################################################################
#
# init_root_sh() - create initial part of root.sh script 
#
###################################################################################

init_root_sh(){

    ROOT_SH=$SCRIPT_DIR/root.sh

    # we have to handle different situations where there is already a root.sh script
    if [ -f $ROOT_SH ]; then

        if [ $(cat $ROOT_SH | wc -l) -eq 3 ]; then

            # this is the dummy script stating just 'Nothing to do', we will remove it
            rm $ROOT_SH
            
        elif [ $(cat $ROOT_SH | wc -l) -eq 1 ]; then
        
            # this can only happen if a previous FM job has failed so that we were not 
            # able to run the finalize_root_sh() function
            rm $ROOT_SH
            
        else
            
            # this is the case, where an old root.sh script is already there and has not
            # been run or stepped into a failure while running it. We will rename it
            mv $ROOT_SH ${ROOT_SH}_not-run_or_partly-run_$(date '+%F_%H-%M-%S')
            
        fi      
        
    fi

    # we will create now an empty skeleton file with just the header line
    echo '#!/bin/bash' > $ROOT_SH

    # various checks will add later on the actual content to be performed as root user
    # after the Fleet Maintenance jobs has been done.
    #

    # make the script executable
    chmod 755 $ROOT_SH     

}

###################################################################################
#
# finalize_root_sh() - remove root.sh if no root actions required
#
###################################################################################

finalize_root_sh(){

    # replace ROOT_SH if it still does have only the the original header line which means that nothing got added
    if [ $(cat $ROOT_SH | wc -l) -eq 1 ]; then

        # we will add a line stating "Nothing to do"
        echo 'echo "Nothing to do"' >> $ROOT_SH
    
        # finally the dummy script should delete itself
        echo '/usr/bin/rm $0' >> $ROOT_SH
    
    else
    
        # one or more checks have added content to the root.sh file. We will now add a final
        # line to the end of script to rename itself to "root.sh_done_at_<date>" when done

        echo "mv \$0 \${0}_done_at_\$(date '+%F_%H-%M-%S')" >> $ROOT_SH
    fi          

}

###################################################################################
#
# setup environment for UPDATE_GI and ROLLBACK_GI
#
###################################################################################

setup_env_UPDATE_ROLLBACK_GI(){

    echo "Setting up environment"

    # we are upgrading/rolling back from OLD_GI_HOME to NEW_GI_HOME
    OLD_GI_HOME=$SOURCE_HOME_LOCATION
    NEW_GI_HOME=$NEW_ORACLE_HOME_LOCATION
    echo "OLD_GI_HOME = $OLD_GI_HOME"
    echo "NEW_GI_HOME = $NEW_GI_HOME"
    echo

    # the current GI_HOME has already been set right at the top of the script
    # to determine the name of all RAC nodes, GI_HOME/bin is in PATH as well

    # determine DB_HOME (in case there are multiple RAC DBs running, 
    # we are assuming they are using the same DB_HOME)
    DB_SERVICE_NAME=$(crsctl stat res -t | grep '^ora\..*\.db$' | head -1)
    DB_HOME=$(crsctl stat res $DB_SERVICE_NAME -p | grep '^ORACLE_HOME=' | cut -d= -f2)
}

###################################################################################
#
# setup environment for UPDATE_RACDB 
#
###################################################################################

setup_env_UPDATE_RACDB(){

    echo "Setting up environment"

    # we are upgrading from OLD_DB_HOME to NEW_DB_HOME
    OLD_DB_HOME=$SOURCE_HOME_LOCATION
    NEW_DB_HOME=$NEW_ORACLE_HOME_LOCATION
    echo "OLD_DB_HOME = $OLD_DB_HOME"
    echo "NEW_DB_HOME = $NEW_DB_HOME"
    echo

    # We will use $target_name to determine DB_NAME
    #
    # Example: $target_name=czcholsint2485/6_FLEETRAC where DB NAME is FLEETRAC  
    DB_NAME=$(echo $target_name | cut -d_ -f2)
    DB_SERVICE_NAME="ora.${DB_NAME,,}.db"      # ensure to convert DB_NAME to lowercase
    
    # the current GI_HOME has already been set right at the top of the script
    # to determine the name of all RAC nodes, GI_HOME/bin is in PATH as well

}

###################################################################################
#
# setup environment for ROLLBACK_RACDB prepatch
#
###################################################################################

setup_env_ROLLBACK_RACDB_prepatch(){

    echo "Setting up environment"

    # We will use $target_name to determine DB_NAME
    #
    # Example: $target_name=czcholsint2485/6_FLEETRAC where DB NAME is FLEETRAC  
    DB_NAME=$(echo $target_name | cut -d_ -f2)
    DB_SERVICE_NAME="ora.${DB_NAME,,}.db"      # ensure to convert DB_NAME to lowercase

    # we are rolling back from OLD_DB_HOME to NEW_DB_HOME
    OLD_DB_HOME=$(crsctl stat res $DB_SERVICE_NAME -p | grep '^ORACLE_HOME=' | cut -d= -f2)
    NEW_DB_HOME=$NEW_ORACLE_HOME_LOCATION
    echo "OLD_DB_HOME = $OLD_DB_HOME"
    echo "NEW_DB_HOME = $NEW_DB_HOME"
    echo

    # the current GI_HOME has already been set right at the top of the script
    # to determine the name of all RAC nodes, GI_HOME/bin is in PATH as well

}

###################################################################################
#
# setup environment for ROLLBACK_RACDB postpatch
#
###################################################################################

setup_env_ROLLBACK_RACDB_postpatch(){

    echo "Setting up environment"

    # We will use $target_name to determine DB_NAME
    #
    # Example: $target_name=czcholsint2485/6_FLEETRAC where DB NAME is FLEETRAC  
    DB_NAME=$(echo $target_name | cut -d_ -f2)
    DB_SERVICE_NAME="ora.${DB_NAME,,}.db"    # ensure to convert DB_NAME to lowercase

    # we are rolling back from OLD_DB_HOME to NEW_DB_HOME
    OLD_DB_HOME=$(crsctl stat res $DB_SERVICE_NAME -p | grep '^ORACLE_HOME_OLD=' | cut -d= -f2)
    NEW_DB_HOME=$NEW_ORACLE_HOME_LOCATION
    echo "OLD_DB_HOME = $OLD_DB_HOME"
    echo "NEW_DB_HOME = $NEW_DB_HOME"
    echo

    # the current GI_HOME has already been set right at the top of the script
    # to determine the name of all RAC nodes, GI_HOME/bin is in PATH as well

}

###################################################################################
#
# Add needed custom procedures below and call them during the appropiate
# FM operation in the 'case' commands at the end of this script. 
#
###################################################################################


###################################################################################
#
# ROLLBACK_GI: copy tnsnames.ora to original GI_HOME/network/admin directory
#
###################################################################################

copy_tnsnames_ora_to_original_GI_HOME(){

    CHECK_NAME="mv tnsnames.ora back to original GI_HOME/network/admin directory"
    echo "Running: $CHECK_NAME"
    echo

    #
    # expected config looks like this:
    #
    # NEW_GI_HOME/network/admin/tnsnames.ora -> DB_HOME/network/admin/tnsnames.ora
    #
        
    # we are running this in prepatch of ROLLBACK_GI, we do not need to take care of 
    # $GI_HOME/network/admin/tnsnmaes.ora in UPDATE_GI, tnsnames.ora gets copied correctly 
    # to NEW_GI_HOME even if it is a symbolic link. Only ROLLBACK_GI is not moving it to new GI_HOME.
        
    OLD_GI_TNSNAMES_ORA=$OLD_GI_HOME/network/admin/tnsnames.ora
    NEW_GI_TNSNAMES_ORA=$NEW_GI_HOME/network/admin/tnsnames.ora
    
    if [ -x "$OLD_GI_TNSNAMES_ORA" ]; then
        # OLD_GI_TNSNAMES_ORA exists
        if [ -x "$NEW_GI_TNSNAMES_ORA" ]; then
            # new tnsnames.ora exists already
            if ls -l $NEW_GI_TNSNAMES_ORA | grep -q $DB_HOME; then
                # NEW_GI_TNSNAMES_ORA is a symbolic link and pointing already to tnsnames.ora located in DB_HOME
                echo "Symbolic link $NEW_GI_TNSNAMES_ORA is already in place and correct:"
                ls -l $NEW_GI_TNSNAMES_ORA
            else
                # remove existing tnsnames.ora file
                rm $NEW_GI_TNSNAMES_ORA
                
                # copy tnsnames.ora to new GI_HOME
                cp -P $OLD_GI_TNSNAMES_ORA $NEW_GI_HOME/network/admin
                
                echo "copied tnsnames.ora from old GI_HOME/network/admin to new GI_HOME/network/admin"
                ls -l $NEW_GI_TNSNAMES_ORA
            fi
        else
                # copy tnsnames.ora to new GI_HOME
                cp -P $OLD_GI_TNSNAMES_ORA $NEW_GI_HOME/network/admin
                
                echo "copied tnsnames.ora from old GI_HOME/network/admin to new GI_HOME/network/admin"
                ls -l $NEW_GI_TNSNAMES_ORA
        fi
    else    
        echo "Nothing to do, $OLD_GI_TNSNAMES_ORA does not exist"
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo
        
}



###################################################################################
#
# copy tnsnames.ora to new DB_HOME and recreate symbolic link in GI_HOME
#
###################################################################################

check_tnsnames_ora(){

    CHECK_NAME="copy tnsnames.ora to new DB_HOME and recreate symbolic link in GI_HOME"
    echo "Running: $CHECK_NAME"
    echo

    #
    # expected config looks like this:
    #
    # GI_HOME/network/admin/tnsnames.ora -> DB_HOME/network/admin/tnsnames.ora
    #
        
    # we are running this for UPDATE_RACDB and ROLLBACK_RACDB in prepatch script
    # so that tnsnames.ora is already in place when the listener gets restarted
    
    # we do not need to take care of $GI_HOME/network/admin/tnsnmaes.ora in UPDATE_GI
    # or ROLLBACK_GI,  tnsnames.ora gets copied correctly to NEW_GI_HOME even 
    # if it is a symbolic link

    OLD_DB_TNSNAMES_ORA=$OLD_DB_HOME/network/admin/tnsnames.ora
    NEW_DB_TNSNAMES_ORA=$NEW_DB_HOME/network/admin/tnsnames.ora

    GI_TNSNAMES_ORA=$GI_HOME/network/admin/tnsnames.ora

    if [ -h "$GI_TNSNAMES_ORA" ]; then
        # GI_TNSNAMES_ORA exists and is a symbolic link
        if [ -f "$OLD_DB_TNSNAMES_ORA" ]; then
            # old tnsnames.ora exists
            if ls -l $GI_TNSNAMES_ORA | grep -q $OLD_DB_TNSNAMES_ORA; then
                # copy tnsnames.ora to new DB_HOME
                cp $OLD_DB_TNSNAMES_ORA $NEW_DB_TNSNAMES_ORA
                
                # remove old link
                rm $GI_TNSNAMES_ORA

                # create new link pointing to new DB_HOME
                ln -s $NEW_DB_TNSNAMES_ORA $GI_TNSNAMES_ORA
                
                echo "copied tnsnames.ora to $NEW_DB_TNSNAMES_ORA"
                echo "ls -l NEW_DB_TNSNAMES_ORA"
                ls -l $NEW_DB_TNSNAMES_ORA

                echo
                echo "created symbolic link from GI_HOME to new DB_HOME:"
                ls -l $GI_TNSNAMES_ORA
            elif ls -l $GI_TNSNAMES_ORA | grep -q $NEW_DB_TNSNAMES_ORA; then
                echo "Nothing to do GI_TNSNAMES_ORA is already pointing to NEW_DB_TNSNAMES_ORA"
                echo "ls -l $GI_TNSNAMES_ORA"
                ls -l $GI_TNSNAMES_ORA
            else
                echo "ERROR: sanity check failed, existing symbolic link is not pointing to any DB_HOME"
                ls -l $GI_TNSNAMES_ORA
            fi
        else
                echo "ERROR: sanity check failed, $OLD_DB_TNSNAMES_ORA not found"
        fi
    else
        echo "Nothing to do, $GI_TNSNAMES_ORA is not a symbolic link or does not exist"
    fi
    echo
    echo "Done with: $CHECK_NAME"
    echo
        
}

check_tnsnames_ora_postpatch(){

    CHECK_NAME="verifying tnsnames.ora fix"
    echo "Running: $CHECK_NAME"
    echo

    GI_TNSNAMES_ORA=$GI_HOME/network/admin/tnsnames.ora

    if [ -h "$GI_TNSNAMES_ORA" ]; then
        echo "ls -l $GI_TNSNAMES_ORA"
        ls -l $GI_TNSNAMES_ORA
        echo "ls -lL $GI_TNSNAMES_ORA"
        ls -lL $GI_TNSNAMES_ORA
    else
        echo "Nothing to do, $GI_TNSNAMES_ORA is not a symbolic link or does not exist"
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo

}

###################################################################################
#
# check/fix symbolic link DB_HOME/network/admin/listener.ora 
#
###################################################################################

check_listener_ora(){

    CHECK_NAME="check/fix symbolic link DB_HOME/network/admin/listener.ora"
    echo "Running: $CHECK_NAME"
    echo

    #
    # expected config looks like this:
    #
    # DB_HOME/network/admin/listener.ora -> GI_HOME/network/admin/listener.ora
    #
        
    # we are running this for UPDATE_GI and ROLLBACK_GI in prepatch script
    # so that the link is already correct in place when the listener gets migrated/restarted

    OLD_GI_LISTENER_ORA=$OLD_GI_HOME/network/admin/listener.ora
    NEW_GI_LISTENER_ORA=$NEW_GI_HOME/network/admin/listener.ora

    DB_LISTENER_ORA=$DB_HOME/network/admin/listener.ora

    if [ -h "$DB_LISTENER_ORA" ]; then
        # DB_LISTENER_ORA exists and is a symbolic link
        if [ -f "$OLD_GI_LISTENER_ORA" ]; then
            # old listener.ora exists
            if ls -l $DB_LISTENER_ORA | grep -q $OLD_GI_LISTENER_ORA; then
                # copy listener.ora to new GI_HOME to ensure that we have a non-broken symbolic link
                # we are running this check in prepatch, the actual UPDATE_GI/ROLLBACK_GI job
                # will re-do this later on and overwrite our copied-over listener.ora file
                cp $OLD_GI_LISTENER_ORA $NEW_GI_LISTENER_ORA
                
                # remove old link
                rm $DB_LISTENER_ORA

                # create new link pointing to new GI_HOME
                ln -s $NEW_GI_LISTENER_ORA $DB_LISTENER_ORA
                
                echo "copied listener.ora to $NEW_GI_LISTENER_ORA"
                echo "ls -l NEW_GI_LISTENER_ORA"
                ls -l $NEW_GI_LISTENER_ORA

                echo
                echo "created symbolic link from DB_HOME to new GI_HOME:"
                ls -l $DB_LISTENER_ORA
                echo
            else
                echo "ERROR: sanity check failed, existing symbolic link is not pointing to old DB_HOME"
                ls -l $DB_LISTENER_ORA
            fi
        else
            echo "ERROR: sanity check failed, $OLD_GI_LISTENER_ORA not found"
        fi
    else
        echo "Nothing to do, $DB_LISTENER_ORA is not a symbolic link or does not exist"
    fi

    echo "Done with: $CHECK_NAME"
    echo
        
}

check_listener_ora_postpatch(){

    CHECK_NAME="verifying listener.ora fix"
    echo "Running: $CHECK_NAME"
    echo

    # this checks needs to be run in all 4 types of jobs
    # in UPDATE_GI/ROLLBACK_GI it is just a check if everything looks like we have done it in prepatch
    # in UPDATE_RACDB/ROLLBACK_RACDB we need to check if we have to copy the listener.ora file/symlink

    if [ "$MAINTENANCE_PURPOSE" = "UPDATE_GI" -o "$MAINTENANCE_PURPOSE" = "ROLLBACK_GI" ]; then
        DB_LISTENER_ORA=$DB_HOME/network/admin/listener.ora
        if [ -h "$DB_LISTENER_ORA" ]; then
            echo "ls -l $DB_LISTENER_ORA"
            ls -l $DB_LISTENER_ORA
            echo "ls -lL $DB_LISTENER_ORA"
            ls -lL $DB_LISTENER_ORA
        else
            echo "Nothing to do, $DB_LISTENER_ORA is not a symbolic link or does not exist"
        fi
    else
        # we are in UPDATE_RACDB / ROLLBACK_RACDB
        NEW_DB_LISTENER_ORA=$NEW_DB_HOME/network/admin/listener.ora
        OLD_DB_LISTENER_ORA=$OLD_DB_HOME/network/admin/listener.ora
        if [ -h "$NEW_DB_LISTENER_ORA" ]; then
            # we have already a symbolic link in NEW_DB_HOME, we need to check if it is correct
            if ls -l $NEW_DB_LISTENER_ORA | grep -q "$GI_HOME/network/admin/listener.ora"; then
                echo "listener.ora in new DB_HOME is pointing to GI_HOME/network/admin/listener.ora"
                ls -l $NEW_DB_LISTENER_ORA
            else
                # we will recreate the symbolic link
                rm $NEW_DB_LISTENER_ORA
                ln -s $GI_HOME/network/admin/listener.ora $NEW_DB_LISTENER_ORA
                echo "created listener.ora symlink in new DB_HOME pointing to GI_HOME/network/admin/listener.ora"
                ls -l $NEW_DB_LISTENER_ORA
            fi
        elif [ ! -f "$NEW_DB_LISTENER_ORA" ]; then
            # no file or symbolic link there
            # let's check if we have a symlink in old DB_HOME
            if [ -h "$OLD_DB_LISTENER_ORA" ]; then
                # yes we had one, we will create one in new DB_HOME as well
                ln -s $GI_HOME/network/admin/listener.ora $NEW_DB_LISTENER_ORA
                echo "created listener.ora symlink in new DB_HOME pointing to GI_HOME/network/admin/listener.ora"
                ls -l $NEW_DB_LISTENER_ORA
            elif [ -f "$OLD_DB_LISTENER_ORA" ]; then
                # we have a plain listener.ora file in old DB_HOME, we will copy it to new DB_HOME as well
                cp $OLD_DB_LISTENER_ORA $NEW_DB_LISTENER_ORA
                echo "copied plain listener.ora file from old DB_HOME to new DB_HOME" 
            else
                echo "no listener.ora file found in old DB_HOME, we will not create a link or file in new DB_HOME"
            fi    
        fi
        
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo

}

###################################################################################
#
# verify/fix TFA config 
#
###################################################################################

check_tfa_config(){

    CHECK_NAME="verify/fix TFA config to ensure that it is running from NEW GI HOME"
    echo "Running: $CHECK_NAME"
    echo

    # check should get run as postpatch in UPDATE_GI and ROLLBACK_GI

    TFA_PROCESS=$(ps -ef | grep TFAMain | egrep -v 'grep')

    if echo $TFA_PROCESS | grep -q "${OLD_GI_HOME}/"; then
        echo "TFA daemon process has been started from OLD_GI_HOME:"
        echo "$TFA_PROCESS"
        echo
        echo "TFA config needs to be fixed and TFA daemon restarted afterwards" 
        echo
        echo "Adding a fix for this to file $ROOT_SH"
        echo
        echo "Please, run '$ROOT_SH' as user 'root' when this job has finished!"
        echo

        cat <<EOF >>$ROOT_SH

#
# TFA config needs to be fixed and TFA daemon restarted afterwards
#
# Replacing old GI_HOME with new GI_HOME
#
echo 'Fixing TFA config'
sed -i 's@^CRS_HOME=$OLD_GI_HOME\$@CRS_HOME=$NEW_GI_HOME@' $NEW_GI_HOME/tfa/*/tfa_home/tfa_setup.txt
sed -i 's@^JAVA_HOME=$OLD_GI_HOME/@JAVA_HOME=$NEW_GI_HOME/@' $NEW_GI_HOME/tfa/*/tfa_home/tfa_setup.txt
sed -i 's@^PERL=$OLD_GI_HOME/@PERL=$NEW_GI_HOME/@' $NEW_GI_HOME/tfa/*/tfa_home/tfa_setup.txt
echo 'Restarting TFA Daemon'
$NEW_GI_HOME/tfa/bin/tfactl stop >/dev/null 2>&1
$NEW_GI_HOME/tfa/bin/tfactl start >/dev/null 2>&1

EOF
    else
        echo "TFA config looks good!"
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo
}

###################################################################################
#
# stop BACKUP_VIP resource and service to address CRS bug 29799836 
#
###################################################################################

stop_backup_vip_service(){
    if $THIS_IS_LAST_NODE; then
        CHECK_NAME="stopping BACKUP_VIP resource and service"
        echo "Running: $CHECK_NAME"
        echo

        BACKUP_VIP_RESOURCE_NAMES=/tmp/BACKUP_VIP_RESOURCE_NAMES.$$

        for VIP_RESOURCE in $(crsctl stat res -t| egrep -i "backup.*vip" | grep -v '^ora\.')
        do 
            crsctl stat res "$VIP_RESOURCE" -p 2>/dev/null | grep -q -i "^STOP_DEPENDENCIES=.*ora\.${DB_NAME}\..*\.svc" && echo $VIP_RESOURCE
        done >$BACKUP_VIP_RESOURCE_NAMES


        if [ -s $BACKUP_VIP_RESOURCE_NAMES ]; then

            for BACKUP_VIP_RESOURCE in $(cat $BACKUP_VIP_RESOURCE_NAMES)
            do
                BACKUP_SERVICE=$(crsctl stat res "$BACKUP_VIP_RESOURCE" -p | \
                    grep -i "^STOP_DEPENDENCIES=.*ora\.${DB_NAME}\..*\.svc" | \
                    sed "s/^.*ora\.${DB_NAME,,}\.//;s/\.svc.*\$//")
                echo "crsctl stop res $BACKUP_VIP_RESOURCE"
                crsctl stop res $BACKUP_VIP_RESOURCE
                echo
                echo "srvctl stop service -d $DB_NAME -s $BACKUP_SERVICE"
                srvctl stop service -d $DB_NAME -s $BACKUP_SERVICE
            done

        else
            echo "no <BACKUP_*_VIP> resource found"
        fi
    
        rm -f $BACKUP_VIP_RESOURCE_NAMES

        echo
        echo "Done with: $CHECK_NAME"
        echo
    fi
}

###################################################################################
#
# start BACKUP_VIP service again
#
###################################################################################

start_backup_vip_service(){
    if $THIS_IS_LAST_NODE; then
        CHECK_NAME="starting BACKUP_VIP resource and service"
        echo "Running: $CHECK_NAME"
        echo

        BACKUP_VIP_RESOURCE_NAMES=/tmp/BACKUP_VIP_RESOURCE_NAMES.$$

        for VIP_RESOURCE in $(crsctl stat res -t| egrep -i "backup.*vip" | grep -v '^ora\.')
        do 
            crsctl stat res "$VIP_RESOURCE" -p 2>/dev/null | grep -q -i "^STOP_DEPENDENCIES=.*ora\.${DB_NAME}\..*\.svc" && echo $VIP_RESOURCE
        done >$BACKUP_VIP_RESOURCE_NAMES


        if [ -s $BACKUP_VIP_RESOURCE_NAMES ]; then
        
            DB_STATUS=$(crsctl stat res $DB_SERVICE_NAME -p | grep '^USR_ORA_OPEN_MODE=' | cut -d= -f2)
            
            # we will only start the BACKUP_*_VIP resource if the DB is in open state
            if [ "${DB_STATUS,,}" = "open" ]; then
                for BACKUP_VIP_RESOURCE in $(cat $BACKUP_VIP_RESOURCE_NAMES)
                do
                    echo "crsctl start res $BACKUP_VIP_RESOURCE"
                    crsctl start res $BACKUP_VIP_RESOURCE
                done
            else
                echo "DB Status is '$DB_STATUS', we will not start resource(s) '$(cat $BACKUP_VIP_RESOURCE_NAMES)'"
            fi     
        else
            echo "no <BACKUP_*_VIP> resource found"
        fi
    
        rm -f $BACKUP_VIP_RESOURCE_NAMES

        echo
        echo "Done with: $CHECK_NAME"
        echo
    fi
}

###################################################################################
#
# check content of /etc/oracle/olr.loc
#
###################################################################################

check_olr_loc_config(){
    CHECK_NAME="verifying content of /etc/oracle/olr.loc"
    echo "Running: $CHECK_NAME"
    echo

    # check should get run as postpatch in ROLLBACK_GI

    #
    # this custom postpatch action will address this bug:
    #
    # BUG 30007337 - SWITCHING GI HOMES ON 18C MAY SET THE INCORRECT OLR LOCATION IN 
    #
    # this effects DB versions 12.2 and 18.x
    # 
    # After ROLLBACK_GI jobs, the file /etc/oracle/olr.loc could
    # still contain the old GI_HOME
    #
    # Example from a broken file after performing ROLLBACK_GI:
    #
    # /etc/oracle$ cat olr.loc
    # olrconfig_loc=/oracle/u01/gi/18.7.0.ONEOFF/cdata/czcholsint2485.olr
    # crs_home=/oracle/u01/gi/18.4.0
    # orplus_config=FALSE
    #
    # File olr.loc is owned by root user. We will add an entry to ROOT_SH in case
    # a fix is required

    OLR_LOC=/etc/oracle/olr.loc

    if [ -f $OLR_LOC ]; then
        if grep -q "^olrconfig_loc=${NEW_GI_HOME}/" $OLR_LOC; then
            echo "File olr.loc looks good, 'olrconfig_loc' contains the correct path using $NEW_GI_HOME"
        else
            echo "File olr.loc is broken, 'olrconfig_loc' contains the wrong path to previous $OLD_GI_HOME"
            echo 
            echo "Adding a fix for this to file $ROOT_SH"
            echo
            echo "Please, run '$ROOT_SH' as user 'root' when this job did finish!" 
            echo
            
            ALERT_LOG=$(lsof -p $(pgrep ocssd.bin) | grep '/crs/trace/ocssd.trc' | sed 's@^.* /@/@;s/ocssd.trc$/alert.log/')

            cat <<EOF >>$ROOT_SH

#
# File olr.loc still contains the path to old GI_HOME
#
# Replacing old GI_HOME with new GI_HOME
#
echo
echo 'Fixing $OLR_LOC'
CURRENT_USED_OLR=\$(grep '^olrconfig_loc=' $OLR_LOC | cut -d= -f2)
sed -i 's@^olrconfig_loc=${OLD_GI_HOME}@olrconfig_loc=${NEW_GI_HOME}@' $OLR_LOC
TO_BE_USED_OLR=\$(grep '^olrconfig_loc=' $OLR_LOC | cut -d= -f2)

echo
echo 'Saving old local repository file'
echo "mv \$TO_BE_USED_OLR \${TO_BE_USED_OLR}_saved_\$(date '+%F_%H-%M-%S')"
mv \$TO_BE_USED_OLR \${TO_BE_USED_OLR}_saved_\$(date '+%F_%H-%M-%S')

echo
echo 'Copying current used local repository file to correct location'
echo "cp \$CURRENT_USED_OLR \$TO_BE_USED_OLR"
cp \$CURRENT_USED_OLR \$TO_BE_USED_OLR
EOF

            if $PERFORM_FULL_CRS_RESTART_IN_ROOT_SH; then
                # we will perform a full CRS restart which will cause all cluster resources to get stopped
                # and restarted on the other node. IMPORTANT: It must be ensured that the 'root.sh' script will 
                # never get run in parallel on both nodes, otherwise it will cause a DB outage!
                
                cat <<EOF >>$ROOT_SH    
echo
echo 'Stopping CRS'
$NEW_GI_HOME/bin/crsctl stop crs -f

echo
echo 'Starting CRS'
$NEW_GI_HOME/bin/crsctl start crs -wait

EOF

            else
                # we will send a HANGUP signal to the ohasd.bin process which will trigger a controlled restart of 
                # CRS control processes without evacuating cluster resources to the other node
                
                cat <<EOF >>$ROOT_SH    
echo
echo 'Sending HUP signal to ohasd.bin process'
kill -HUP \$(pgrep ohasd.bin)

# waiting a few seconds to get processes restarted
sleep 10

# show last lines of CRS alert log
echo
echo "tail -8 $ALERT_LOG"
tail -8 $ALERT_LOG
echo

EOF
            fi
        fi
    else
        echo "ERROR: File $OLR_LOC not found!"
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo
}

###################################################################################
#
# consistency check/fix of pathes in static listener.ora entries
#
###################################################################################

check_pathes_in_listener_ora(){

    CHECK_NAME="check/fix of pathes in static listener.ora entries"
    echo "Running: $CHECK_NAME"
    echo

    # check will run as postpatch for UPDATE_RACDB and ROLLBACK_RACDB

    LISTENER_ORA=$GI_HOME/network/admin/listener.ora

    if [ -f $LISTENER_ORA ]; then
        #
        # Example of a static entry in listener.ora:
        #
        # (ORACLE_HOME = /u01/app/oracle/product/12.2.0.1/dbhome_1)
        #
        if egrep -q "\( *ORACLE_HOME *= *${OLD_DB_HOME} *\)" $LISTENER_ORA; then
            echo "GI_HOME/network/admin/listener.ora contains entries with old DB_HOMEs:"
            egrep "\( *ORACLE_HOME *= *${OLD_DB_HOME} *\)" $LISTENER_ORA

            echo
            echo "Replacing OLD_DB_HOME with NEW_DB_HOME in entries"
            sed -i "s@( *ORACLE_HOME *= *${OLD_DB_HOME} *)@(ORACLE_HOME = ${NEW_DB_HOME})@" $LISTENER_ORA

            echo "new ORACLE_HOME entries in listener.ora:"
            egrep "\( *ORACLE_HOME *=.*\)" $LISTENER_ORA        
        else
            echo "listener.ora does not have entries pointing to old DB_HOME"
        fi
    else
        echo "ERROR: $LISTENER_ORA not found"
    fi

    echo
    echo "Done with: $CHECK_NAME"
    echo

}



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
