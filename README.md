# mariadb_review
SQL Script for Initial Review of MariaDB Server for Support tickets.

This script will create a small schema of a few tables and views called "mariadb_review".

It is important that this script not replicate to a slave so that you can get independent results on each server. Thus, the script is run with:
```
SET SESSION SQL_LOG_BIN=OFF;
```

There are three ways to run this script: quick, long-term, indefinite. *Edit the script* **mariadb_review.sql** and change value for @TIMES_TO_COLLECT_PERF_STATS. Each +1 added to @TIMES_TO_COLLECT_PERF_STATS will extend the total run 1 minute. For a 10 minute run, set it to 10.
- Quick run: Gather performance statistics for a few minutes. 
```
Set @TIMES_TO_COLLECT_PERF_STATS=30;
```

- Long-term run: Gather statistics for a long period. For example to run for 7 days. 
```
set @TIMES_TO_COLLECT_PERF_STATS=(60*24*7);
```

- Indefininte run: Gather statistics for extremely long period, and stop it when ready at some time in the future. 
```
Set @TIMES_TO_COLLECT_PERF_STATS=99999999;
```
You can stop any run from a separate session with this update:
```
update mariadb_review.ITERATION set ID=0 where 1=1;
```
This update will end the script gracefully after 1 minute and populate all of the values in the table SERVER_STATE.
***
Currently, the supported method is running the script as root@localhost, assuming this user has SUPER privilege.
***
Use this syntax to launch this script in the background:
```
mariadb -Ae "source /root/mariadb_review/mariadb_review.sql" > /tmp/mariadb_review.log 2>&1  & disown
```
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
- Topology information such as whether a server is a primary, a replica or a member of a Galera cluster.
- A full list of global variables
- Information about user created objects
- basic performance data that can be used as a baseline

In long-term run, this script can collect WARNINGS such as:
- Long-running transactions that do not commit
- Blocking transactions and waiting transactions
- Transactions that cause seconds-behind-master in a replica
- High redo occupancy


