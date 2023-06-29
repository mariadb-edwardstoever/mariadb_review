# Known risks to running mariadb_review.sql

Avoid problems by using provided scripts stop_collecting.sql and clean_up.sql.

## Stand-alone Topology
For a stand-alone server, there are no known risks to running the mariadb_review.sql script.

## Master/Slave Replication Topology
The mariadb_review.sql turns off replication from a master instance. It is possible to break the slave replicating if you run DML (insert/update/delete) or DDL(create/drop) commands on tables in the mariadb_review schema on the master without setting SQL_LOG_BIN=OFF at the session level. A typical error when reviewing slave status:
```
Last_SQL_Error: Error executing row event: 'Table 'mariadb_review.ITERATION' doesn't exist'
```
If you break replication by running a command in the mariadb_review schema on the primary, follow these steps on the replica to start replication:
```
SET GLOBAL sql_slave_skip_counter = 1;
start slave;
show slave status\G
```

## Galera Cluster Topology
Galera is similar to Master/Slave Replication. If mariadb_review.sql is run on any node, any subsequent command on the tables of the mariadb_review schema could break the cluster.
