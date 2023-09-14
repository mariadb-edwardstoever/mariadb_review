# Known Risks by Running mariadb_review.sql

It is safe to run mariadb_review.sql when you take the following steps in order on a server:
- run mariadb_review.sql
- mariadb-dump the mariadb_review schema and attach to your support ticket
- run the clean_up.sql script
- Finish with one server in your topology before running mariadb_review scripts on another server

Even if you do not follow the steps above, it is unlikely to break replication because the script has safeguards built-in, *but it is possible.*
***

## Possible scenarios to break replication:
- **On a Master**, run mariadb_review.sql with `REPLICATE='NO'` and then login without turning off replication,  (`SESSION SQL_LOG_BIN=ON`) and perform DML or DDL in the mariadb_review schema. This will attempt to replicate to the slave for a schema that does not exist on the slave.
- **On Galera**, run mariadb_review.sql with `REPLICATE='NO'` and then login without turning off replication,  (`SESSION WSREP_ON=ON`) and perform DML or DDL in the mariadb_review schema. This will attempt to replicate to the other Galera nodes for a schema that does not exist.
- **On a Slave**, run  mariadb_review.sql and then run  mariadb_review.sql on the master before running the clean_up.sql on the slave. Even though there are safeguards in the script that should prevent breaking replication, it may still be possible.

There is little risk to running mariadb_review.sql, either REPLICATE=YES or REPLICATE=NO if the clean_up.sql script is run before any DDL (create/alter/drop) or DML (insert/update/delete) are run within the mariadb_review schema.

*Avoid breaking replication by using provided scripts* `stop_collecting.sql` *and* `clean_up.sql`*. Finish with one server in your topology before running mariadb_review scripts on the next server*

## Turning off Replication in the Session
Prior to version 1.7.0, replication was turned off in the session by default. Version 1.7.0 introduces the swith @REPLICATE with a default value 'YES'.

With @REPLICATE='NO', the mariadb_review.sql turns off replication in the session by running the following commands:
```
SET SESSION SQL_LOG_BIN=OFF;
SET SESSION WSREP_ON=OFF;
```
If you are not going to run this script on two or more servers at the same time, you can leave @REPLICATE='YES' as it is generally safer.

## Stand-alone Topology
For a stand-alone server, there is no replication and no risks to running the mariadb_review.sql script. 


## Master/Slave Replication Topology

If you break replication, run these commands on the slave to restart the slave:
```sql
set global replicate_ignore_db='mariadb_review';
start slave;
show slave status\G
```
You can then safely run the clean_up.sql script on the master. Finally, run the clean_up.sql script on the slave. If you like, you can remove the global replicate_ignore_db on the slave:
```sql
set global replicate_ignore_db='';
```

## Galera Cluster Topology
It is possible to get a node kicked from a Galera cluster by running DML(insert/update/delete) or DDL(create/drop) commands on tables in the mariadb_review schema if the schema was created with @REPLICATE='NO'.

You will see these errors:
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
Once the node has joined the cluster, you can safely run the clean_up.sql script on the same node where mariadb_review.sql was run.

