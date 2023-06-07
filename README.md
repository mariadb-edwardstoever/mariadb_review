# mariadb_review
SQL Script for Initial Review of MariaDB Server for Support tickets.

This script will create a small schema of a few tables and views called "mariadb_review".

It is important that this script not replicate to a slave so that you can get independant results on each server. Thus, the script is run
```
SET SESSION SQL_LOG_BIN=OFF;
```

There are three ways to run this script. Edit the script and change values for @TIMES_TO_COLLECT_PERF_STATS and @DROP_OLD_SCHEMA_CREATE_NEW
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
This will end the script gracefully in about 1 minute and populate all of the values in the table SERVER_STATE.
***
Currently, the supported method is running the script as root@localhost, assuming this user has SUPER privilege.
***
Use this syntax to launch this script in the background:
```
mariadb -Ae "source /root/mariadb_review/mariadb_review.sql" > /tmp/mariadb_review.log 2>&1  & disown
```
***
To share the results of the script with support, dump the mariadb_review schema to a SQL text file. Include your support ticket number in the file name:
```
mariadb-dump mariadb_review > CS0577777_mariadb_review.sql
```
To drop the mariadb_review schema without effecting replication, use the script clean_up.sql
```
mariadb < clean_up.sql
```
