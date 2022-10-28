#Dependancy
#import-module awspowershell


# A static class for common low lever operations involving PostGres Aurora Cluster/Instance and PostGres Instance operations.

# Instructions, first call InstallPostgresTools() to use any psql or pg_dump operations.

# Ensure you pass in connection strings for either PSQL or sqlAlchemy, eg:
# postgresql://user:password@dbEndpoint.ap-southeast-2.rds.amazonaws.com:8080/dbname'
# postgresql+psycopg2://user:password@dbEndpoint.ap-southeast-2.rds.amazonaws.com:8080/dbname'


function GetInstanceEndPointAddress($dbInstanceName) {
    $endpoint = aws rds describe-db-instances --db-instance-identifier $dbInstanceName --query "DBInstances[0].Endpoint.Address"
    $endpoint = $endpoint.replace('\r\n', '').replace('"', '')
    return $endpoint
}

function SuccessPSQLConnect {
    param([string]$constr)
    Write-Host "SuccessConnectToDB:"
    $successConnect = .\psql -c 'Select version();' $constr
    if (!($successConnect)) {
        Write-Host "No, Failed!"
        return $false;
    }
    Write-Host " Yes"
    return $true;
}

function DBInstanceExists($dbInstanceName) {
        $dbState = aws rds describe-db-instances --db-instance-identifier $dbInstanceName --query "DBInstances[0].DBInstanceIdentifier"
    Write-Host 'Database: ' + dbState + ' exists'
    return $dbState.length > 0
}
function FixSqlAlchemyConnStrForPSQL {
    param([string]$constr)
    return connstr.replace('+psycopg2','')
    }
    
function GetDBInstanceStatus($dbInstanceName) {
    $dbState = aws rds describe-db-instances --db-instance-identifier $dbInstanceName --query "DBInstances[0].DBInstanceStatus"
    return $dbState
}

function GetDBClusterStatus($dbClusterName) {
    $dbCluserIdentifier = 'DBClusters[?DBClusterIdentifier==`' + $dbClusterName + '`].{Status:Status}'.Replace('''','')
    $dbState = aws rds describe-db-clusters --query $dbCluserIdentifier
    
    #TODO - if needed???
    # res=json.loads(dbState)
    # if len(dbState) > 9:  #ie not equal to   =b'[]\n'
    #     dbState = res[0]['Status']
    #     dbState = dbState.replace('\r\n','').replace('\n','').replace('"','')
    #     print('GetDBClusterStatus: ' + dbState) 
    # else:
    #     return ''

        return $dbState
    }   

    function WaitForDBInstance($dbInstanceName) {
        Write-Host  "Start the ReportingDB if it shut down due to missing tags"
        aws rds start-db-cluster --db-cluster-identifier ReportingDB-cluster 
        $count = 0
        do {
            Start-Sleep -s 20
            $count++
            if ($count -gt 60) {
                exit
            }
            $dbState = aws rds describe-db-instances --db-instance-identifier reportingdb --query "DBInstances[0].DBInstanceStatus"
            $dbState = $dbState.replace("""", "")
        } until ($dbState -eq "stopped" -OR $dbState -eq "available" -OR $dbState -eq "starting")
    }

    function WaitForDBCluster($dbClusterName) {   
        $count = 0
        do {
            Start-Sleep -s 20
            $count++
            if ($count -gt 60) {
                Write-Host 'Timed out starting/stopping the Cluster'
                exit
            }
            $dbCluserIdentifier = 'DBClusters[?DBClusterIdentifier==`' + $dbClusterName + '`].{Status:Status}'.replace('''','')
            $dbState = aws rds describe-db-clusters --query $dbCluserIdentifier

            # #TODO
            # res = json.loads(dbState)
            # dbState = res[0]['Status']
            # dbState = dbState.replace('\r\n','').replace('\n','').replace('"','')
            
            Write-Host 'Waiting For DB Cluster ' + dbClusterName + ', Current State: ' + dbState + ', Count: ' + str(count)
        }  until ($dbState -eq "stopped" -OR $dbState -eq "available" -OR $dbState -eq "starting")
    }
       
    function WaitForDBClusterToBeDeleted($dbClusterName) {
        Write-Host  "Next confirm the ReportingDB-Cluster is no longer listed and is completely gone!"
        $count = 0
        do {
            Start-Sleep -s 20
            $count++
            if ($count -gt 60) {
                exit
            }
            $dbState = aws rds describe-db-clusters --query 'DBClusters[?DBClusterIdentifier==`' + dbClusterName + '`]'
            Write-Host 'Waiting For Cluster to be deleted ' + dbClusterName + ', Current State: ' + dbState + ', Count: ' + count.ToString()
        } until ($dbState.length -lt 5)
    }

    
    function InstallPostgresTools($S3Name) {  
        #TODO - PUT ALL THESE FILES IN A REPOSITORY (EVEN ARTICFACTORY) INSTEAD OF S3

        #Download C++ Redistributable
        aws s3 cp s3://$S3Name/vcredist_x64.exe .
        Write-Hoost 'Silently install the C++ dependency for Windows PSQL.exe'
        start-process -FilePath "vcredist_x64.exe" -ArgumentList "/install /q /norestart" -Verb RunAs -wait

        # Extract PostgresTools into the single diretory for ease of use
        aws s3 cp s3://$S3Name/PostGresTools.zip .
        Expand-Archive -Path PostGresTools.zip -Destination .
    }
   
    function ExecuteSelectSql($connstr, $sql) {
        $data = $sql | .\psql -t $connstr
        return $data
    }

    function ExecuteFileScript($connstr, $fileName) {
        .\psql -f $fileNam $connstr
    }

    function ExecuteSql($connstr, $sql) {
        .\psql -c $sql $connstr
    }

    function CopyDBTable($fromConnStr, $toConnStr, $table) {
        .\pg_dump -C -t $table $fromConnStr | .\psql $toConnStr
    }

    function CloneInstanceDatabaseByTakingSnapshotAndRestoring($dbInstanceIdentifierToBeBackedUp, $dbSnapShotName, $waitTillComplete = $False) {
        Write-Host  'Delete existing ' + $dbSnapShotName + ' snapshot'
        aws rds delete-db-snapshot --db-snapshot-identifier $dbSnapShotName
        
        Write-Host  'Backup ' + $dbInstanceIdentifierToBeBackedUp + ' as snapshot'
        aws rds create-db-snapshot --db-snapshot-identifier $dbSnapShotName --db-instance-identifier  $dbInstanceIdentifierToBeBackedUp
        
        Write-Host 'Wait till the ' + $dbInstanceIdentifierToBeBackedUp + ' snapshot called ' + $dbInstanceIdentifierToBeBackedUp + ' is ready'
        aws rds wait db-snapshot-completed --db-snapshot-identifier $dbSnapShotName --db-instance-identifier  $dbInstanceIdentifierToBeBackedUp
        
        Write-Host  'Restore ' + $dbSnapShotName + ' snapshot as ' + $dbInstanceIdentifierToBeBackedUp
        aws rds restore-db-instance-from-db-snapshot --db-instance-identifier $dbSnapShotName --db-snapshot-identifier $dbSnapShotName  --db-instance-class db.t3.small --engine postgres --port 8080 --db-subnet-group-name reportingdb-rdsdbsubnetgroup-555gwx43t --vpc-security-group-ids sg-02ade32dc5f89ef9e --db-parameter-group-name default.postgres9.6

        if ($waitTillComplete)
        {
            Write-Host  "Detection to wait till the CertRegDup Database is ready"
            aws rds wait db-instance-available --db-instance-identifier CertRegDup
        }
    }

    function CloneClusterDatabaseByTakingSnapshotAndRestoring($dbClusterIdentifier, $dbInstanceIdentifier, $port,$subnetGroupName, $vpcSecurityGroupID, $kmsKeyID, $dbClusterParameterGroupName, $ApplicationIDTag, $CostCentreTag, $dbClusterARNForTargetToBeCloned, $dbClusterARNForDestOfClone, $dbInstanceARNForDestOfClone, $waitTillComplete = $False, $ec2Size='db.r4.large', $deleteExistingSnapShotName = '') {
        
        if (deleteExistingSnapShotName != '')
        {
            Write-Host  "Delete " + $deleteExistingSnapShotName  + " cluster snapshot (fails silently if it doesn't exists)"
            aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier $deleteExistingSnapShotName
            aws rds wait db-cluster-snapshot-deleted --db-cluster-snapshot-identifier $dbInstanceIdentifier --db-cluster-identifier $dbClusterIdentifier
        }        
                
        Write-Host  'Make a snapshot of '  + dbClusterARNForTargetToBeCloned
        aws rds restore-db-cluster-to-point-in-time --source-db-cluster-identifier arn:aws:rds:ap-southeast-2:728669675925:cluster:ncg-aurora-cluster-rdsdbcluster-1j881okx7me6r --db-cluster-identifier ReportingDB-cluster --restore-type copy-on-write --use-latest-restorable-time --port 8080 --db-subnet-group-name reportingdb-rdsdbsubnetgroup-555gwx43t --vpc-security-group-ids sg-02ade32dc5f89ef9e --kms-key-id a629d52c-9cff-46ee-bbcd-7ce97853a72a --db-cluster-parameter-group-name default.aurora-postgresql10
        
        # Mandatory Tagging
        multipleTagsInJSON = '[{"Key" : "CostCentre","Value" : "' + CostCentreTag + '"}, {"Key" : "ApplicationID","Value" : "' + ApplicationIDTag + '"}]'
        
        Write-Host 'Create cluster dB from ' + dbClusterIdentifier + ' snapshot'
        aws rds create-db-instance --db-cluster-identifier ReportingDB-cluster --db-instance-identifier ReportingDB --db-instance-class db.r4.large --tags multipleTagsInJSON --engine aurora-postgresql --monitoring-interval 0
        
        # We wait for the cluster to be available
        WaitForDBCluster($dbClusterIdentifier)
        # then we wait for the instance to become - not available because as soon as it does, CPS switch both the Cluster and Instance off
        WaitForDBInstance($dbInstanceIdentifier)
       

        # Over the top protection, make sure if its Stopped then we start it
        if ($waitTillComplete){
            Write-Host 'AGAIN - Creating Databases without Tags get switched off by CPS, and we can''t specify tags on dB CLUSTER-Instance creation. So we give CPS a few minutes to apply their change and turn off the db.'
            time.sleep(120)
            StartClusterAndInstance(dbClusterIdentifier, dbInstanceIdentifier, isWindows)
        }

    function StartClusterAndInstance($dbClusterIdentifier, $dbInstanceIdentifier) {        
        Write-Host 'Start the ' + $dbClusterIdentifier + ' and make sure the instance is available'
        WaitForDBCluster($dbClusterIdentifier)
        
        Write-Host 'Start the ' + $dbClusterIdentifier 
        aws rds start-db-cluster --db-cluster-identifier  $dbClusterIdentifier

        Write-Host  "Detection to wait till the " + $dbInstanceIdentifier + " Database is ready"
        aws rds wait db-instance-available --db-instance-identifier $dbInstanceIdentifier
        WaitForDBCluster(dbClusterIdentifier)
    }

    function DeleteClusterAndInstance($dbClusterIdentifier, $dbInstanceIdentifier, $dbSnapShotName, $waitTillComplete = $False) {
        Write-Host 'Start the ' + $dbClusterIdentifier + ' and make sure the instance is available'
        WaitForDBCluster($dbClusterIdentifier)
       
        Write-Host 'Start the ' + $dbClusterIdentifier 
        aws rds start-db-cluster --db-cluster-identifier  $dbClusterIdentifier

        Write-Host "Detection to wait till the " + $dbInstanceIdentifier + " Database is ready"
        aws rds wait db-instance-available --db-instance-identifier $dbInstanceIdentifier

        Write-Host  "Delete ' + $dbInstanceIdentifier + ' instance (fails silently if DB doesn't exist)"
        aws rds delete-db-instance --db-instance-identifier  $dbInstanceIdentifier --skip-final-snapshot --delete-automated-backups

        Write-Host  "Delete ' + $dbClusterIdentifier + ' cluster snapshot (fails silently if it exists)"
        aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier $dbSnapShotName
        aws rds wait db-cluster-snapshot-deleted --db-cluster-snapshot-identifier $dbSnapShotName --db-cluster-identifier  $dbInstanceIdentifier

        Write-Host  "Delete ' + $dbClusterIdentifier + ' cluster database (fails silently if it exists)"
        aws rds delete-db-cluster --db-cluster-identifier $dbClusterIdentifier --no-skip-final-snapshot --final-db-snapshot-identifier $dbSnapShotName

        Write-Host  "Detection to wait till the " + $dbInstanceIdentifier + " Database instance is deleted (if it exists)"
        aws rds wait db-instance-deleted --db-instance-identifier $dbInstanceIdentifier

        if ($waitTillComplete){
            WaitForDBClusterToBeDeleted($dbClusterIdentifier)
        }
    }
  