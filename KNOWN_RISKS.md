# Known risks to running mariadb_review.sql

Avoid problems by using provided scripts stop_collecting.sql and clean_up.sql.

## Turning off Replication
The mariadb_review.sql turns off replication by running the following commands:
```
SET SESSION SQL_LOG_BIN=OFF;
SET SESSION WSREP_ON=OFF;
```
This is done to ensure that data collected from one instance is not confused with data collected on another instance.

## Stand-alone Topology
For a stand-alone server, there are no known risks to running the mariadb_review.sql script. If you want to log the commands to binary logs, comment out or remove the line `SET SESSION SQL_LOG_BIN=OFF;`.


## Master/Slave Replication Topology
It is possible to break a slave replicating if you run DML(insert/update/delete) or DDL(create/drop) commands on tables in the mariadb_review schema on the master without first running `SET SQL_LOG_BIN=OFF`. A typical error when reviewing slave status:
```
Last_SQL_Error: Error executing row event: 'Table 'mariadb_review.ITERATION' doesn't exist'
```
If you break replication by running a command in the mariadb_review schema on the primary, run these commands on the slave to start replication:
```
SET GLOBAL sql_slave_skip_counter = 1;
start slave;
show slave status\G
```

## Galera Cluster Topology
It is possible to get a node kicked from the cluster by running DML(insert/update/delete) or DDL(create/drop) commands on tables in the mariadb_review schema on any node without first running `SET SESSION WSREP_ON=OFF;`. You will see these errors:
```
MariaDB [mariadb_review]> SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment';
+---------------------------+--------------+
| Variable_name             | Value        |
+---------------------------+--------------+
| wsrep_local_state_comment | Inconsistent |
+---------------------------+--------------+

MariaDB [my_schema]> update my_table set my_col=223 where id=7;
ERROR 1047 (08S01): WSREP has not yet prepared node for application use
MariaDB [my_schema]>
```
The solution is to perform an SST by restarting the mariadb instance:
```
root@m1:~$ systemctl restart mariadb
root@m1:~$ mariadb -Ae "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment';"
+---------------------------+--------+
| Variable_name             | Value  |
+---------------------------+--------+
| wsrep_local_state_comment | Synced |
+---------------------------+--------+
root@m1:~$
```

