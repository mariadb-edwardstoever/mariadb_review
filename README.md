# mariadb_review
## SQL Script for Initial Review of MariaDB Server for Support tickets.

## Read these instructions carefully
To download the mariadb_review script direct to your linux server, you may use git or wget:
```
git https://github.com/mariadb-edwardstoever/mariadb_review.git
```
```
wget https://github.com/mariadb-edwardstoever/mariadb_review/archive/refs/heads/main.zip
```
***
```diff
@@ Important note about Galera and Replication Topologies  @@

The mariadb_review.sql script does not replicate to other instances. 
This ensures that the data collected for an instance remains only on that instance. 
Replication is disabled in the session using these two commands:
SET SESSION SQL_LOG_BIN=OFF; 
SET SESSION WSREP_ON=OFF;

Be aware that you will break replication and/or galera cluster if you perform 
DDL or DML on the mariadb_review schema without turning off replication in 
your session. Avoid breaking replication. Use only use the provided scripts 
stop_collecting.sql and clean_up.sql to make DDL or DML changes to the 
mariadb_review schema.

For information about fixing this problem if it occurs, read the included file KNOWN_RISKS.md.
```

This script will create a small schema of a few tables and views called "mariadb_review".

There are three ways to run this script: quick, long-term, indefinite. *Edit the script* **mariadb_review.sql** and change value for @MINUTES_TO_COLLECT_PERF_STATS. Each +1 added to @MINUTES_TO_COLLECT_PERF_STATS will extend the total run 1 minute. For a 10 minute run, set it to 10.
- Quick run: Gather performance statistics for a few minutes. 
```sql
SET @MINUTES_TO_COLLECT_PERF_STATS=30;
```

- Long-term run: Gather statistics for a long period. For example to run for 7 days. 
```sql
SET @MINUTES_TO_COLLECT_PERF_STATS=(60*24*7);
```

- Indefininte run: Gather statistics for extremely long period, and stop it when ready at some time in the future. 
```sql
SET @MINUTES_TO_COLLECT_PERF_STATS=99999999;
```
***

In most cases, collecting performace statistics once per minute is sufficient. It is useful to collect perf stats frequently when trying to trap a specific event that is visible only breifly. *Edit the script* **mariadb_review.sql** and change value for @COLLECT_PERF_STATS_PER_MINUTE to collect statistics more frequently.

***

If you want to conserve statistics from previous runs of the script, *Edit the script* **mariadb_review.sql** and change value @DROP_OLD_SCHEMA_CREATE_NEW to NO.

***
Currently, the supported method is running the script as root@localhost, assuming this user has SUPER privilege.
***
For a short-term run, you can launch the script from the command-line which will provide some output for your review:
```
mariadb -Ae "source mariadb_review.sql"
```

For a long-term run, use this syntax to run the script in the background:
```
mariadb -Ae "source /root/mariadb_review/mariadb_review.sql" > /tmp/mariadb_review.log 2>&1  & disown
```
***
You can stop any run from a separate session by running the stop_collecting.sql script:
```
mariadb < stop_collecting.sql
```
This script will stop the collection of performance data within 1 minute.
***
To share the results of the script with support, dump the mariadb_review schema to a SQL text file:
```
mariadb-dump mariadb_review > $(hostname)_mariadb_review_run_1.sql
```
You can dump the schema to SQL text file even while the script is running. The information collected up to that point can be reviewed and the script will continue.

To drop the mariadb_review schema without effecting replication, use the script clean_up.sql
```
mariadb < clean_up.sql
```
***
## What information will mariadb_review.sql script provide to MariaDB Support team?
In a quick run, this script will provide the following to MariaDB support:
- General information about the server
- Topology information such as whether a server is a primary, a replica or a member of a Galera cluster
- A full list of global variables
- Information about user created objects
- Basic performance data that can be used as a baseline
- A list of empty tables with large datafiles
- A list of indexes with low cardinality
- A list of tables and counts of primary key, unique, and non-unique indexes
- Statistics for tuning Galera cluster

This script will provide WARNINGS when they occur while collecting performance data, such as:
- Long-running transactions that do not commit
- Blocking transactions and waiting transactions
- Deadlocks
- Transactions that cause seconds-behind-master in a replica
- Transactions that cause flow-control in Galera cluster
- High redo occupancy

