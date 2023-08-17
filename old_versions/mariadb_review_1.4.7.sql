/* MariaDB Review */
/* Script by Edward Stoever for MariaDB Support */

/* TIMES_TO_COLLECT_PERF_STATS is how many times performance stats and warnings will be collected. */
/* Each time adds 1 minute to the run of this script. */
/* Minimum recommended is 10. Must be at least 2 to compare with previous collection. */
/* Disable collection of performance stats setting it to 0.*/
/* You can set @TIMES_TO_COLLECT_PERF_STATS to a very large number to run indefinitely. */
/* Stop the script gracefully by running the stop_collecting.sql script, example: mariadb < stop_collecting.sql */
set @TIMES_TO_COLLECT_PERF_STATS=10;

/* DROP_OLD_SCHEMA_CREATE_NEW = NO in order to conserve data from previous runs of this script. */
/* Conserve runs to compare separate runs. */
set @DROP_OLD_SCHEMA_CREATE_NEW='YES';

/* -------- DO NOT MAKE CHANGES BELOW THIS LINE --------- */
set @MARIADB_REVIEW_VERSION='1.4.7';
set @REDO_WARNING_PCT_THRESHOLD=50;
set @LONG_RUNNING_TRX_THRESHOLD_MINUTES = 10;
set @LARGE_EMPTY_DATAFILE_THRESHOLD = (100 * 1024 * 1024); 
set @LARGE_EMPTY_LOW_ROWCOUNT = 1000;
set @GB_THRESHOLD = (5 * 1024 * 1024 * 1024); -- BELOW THIS NUMBER DISPLAY IN MB ELSE GB
SET @MIN_ROWS_TO_CHECK_INDEX_CARDINALITY=100000;
SET @WARN_LOW_CARDINALITY_PCT=2;
SET @MIN_ROWS_NO_PK_THRESHOLD=10000;
SET @LOW_QUERY_CACHE_HITS_THRESHOLD=10000;
set @ROW_FORMAT_COMPRESSED_THRESHOLD =(512 * 1024 * 1024);
SET @GALERA_LONG_RUNNING_TXN_MS=330;
SET @HISTORY_LIST_LENGTH_THRESHOLD=5000;
SET @DO_NOTHING='NO'; -- SET TO YES WILL CREATE SCHEMA AND DO NOTHING ELSE. USED TO ESCAPE IF PROCESS IS ALREADY RUNNING.

/* ENSURE THIS SCRIPT DOES NOT REPLICATE -- SQL_LOG_BIN=OFF and WSREP_ON=OFF */
SET SESSION SQL_LOG_BIN=OFF; 
/* If not Galera, WSREP_ON=OFF will have no effect. */
SET SESSION WSREP_ON=OFF;

SET SESSION lc_time_names='en_US';

select 'YES' into @CURRENT_RUN_EXISTS from information_schema.TABLES 
where TABLE_SCHEMA='mariadb_review' 
and TABLE_NAME='CURRENT_RUN';

/* DO NOT TOUCH @RUNID! */
select concat('a',substr(md5(rand()),floor(rand()*6)+1,9)) into @RUNID;

delimiter //
begin not atomic
set @PRINCIPAL_VERSION=cast(substring_index(substring_index(version(),'.',1),'.',-1) as integer);
set @POINT_VERSION=cast(substring_index(substring_index(version(),'.',2),'.',-1) as integer);
if NOT @POINT_VERSION REGEXP '^[0-9]+$' then 
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'POINT_VERSION is not numeric.';
end if;
end;
//
delimiter ;

delimiter //
begin not atomic
if @CURRENT_RUN_EXISTS='YES' then
  select 'RUNNING_FROM_ANOTHER_SESSION' into @ALREADY_RUNNING_STATUS 
  from mariadb_review.CURRENT_RUN 
  where ID=1 
  AND RUN_ID != @RUNID 
  AND STATUS != 'COMPLETED' 
  LIMIT 1;
    if @ALREADY_RUNNING_STATUS is not null then
      SET @DO_NOTHING='YES';
      SIGNAL SQLSTATE '01000' 
        SET MESSAGE_TEXT = 'This script appears to be running from another session.',
        MYSQL_ERRNO = 1000;
        show warnings;
    end if;
end if;
end;
//

delimiter ;

select concat('SCRIPT VERSION ',@MARIADB_REVIEW_VERSION) as NOTE;

delimiter //
begin not atomic

if @DROP_OLD_SCHEMA_CREATE_NEW = 'YES' AND @DO_NOTHING != 'YES' THEN
  select concat('Dropping schema mariadb_review to start over.') as NOTE 
  from information_schema.SCHEMATA where SCHEMA_NAME='mariadb_review';
  drop schema if exists mariadb_review;
end if;

end;
//
delimiter ;

/* RENAME EXISTING TABLE */
delimiter //
begin not atomic

select 'YES' into @SERVER_STATE_EXISTS 
from information_schema.TABLES 
where TABLE_SCHEMA='mariadb_review' 
and TABLE_NAME='SERVER_STATE';

if @SERVER_STATE_EXISTS='YES' AND @DO_NOTHING != 'YES' THEN
  select concat('RENAME TABLE mariadb_review.SERVER_STATE TO mariadb_review.SERVER_STATE_OLD_',date_format(str_to_date(`STATUS`,'%Y-%m-%d %H:%i:%S'),'%Y_%m_%d_%H_%i_%S')) into @SQL 
  from mariadb_review.SERVER_STATE where ITEM='REVIEW STARTS'
  and exists (select 'x' from mariadb_review.CURRENT_RUN where ID = 1 and STATUS != 'RUNNING');
  
  if @SQL is not null then
    select concat('Renaming table from SERVER_STATE TO SERVER_STATE_OLD_',date_format(str_to_date(`STATUS`,'%Y-%m-%d %H:%i:%S'),'%Y_%m_%d_%H_%i_%S'),'.')  as `NOTE` from mariadb_review.SERVER_STATE where ITEM='REVIEW STARTS';  
    PREPARE STMT FROM @SQL;
    EXECUTE STMT;
    DEALLOCATE PREPARE STMT;
  end if;
end if;

end;
//
delimiter ;

select concat('Creating schema mariadb_review.') as NOTE 
where not exists (select 'x' from information_schema.SCHEMATA where SCHEMA_NAME='mariadb_review');
create schema if not exists mariadb_review;
use mariadb_review;

CREATE TABLE IF NOT EXISTS `CURRENT_RUN` (
  `ID` int(11) NOT NULL DEFAULT 1,
  `RUN_ID` varchar(12) DEFAULT NULL,
  `RUN_START` timestamp NOT NULL DEFAULT current_timestamp(),
  `RUN_END` timestamp NULL DEFAULT NULL,
  `STATUS` varchar(12) DEFAULT 'RUNNING',
  `STATS_COLLECTED` bigint(20) default 0,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
COMMENT='The CURRENT_RUN table should never have more than 1 row.';

CREATE TABLE IF NOT EXISTS `SERVER_STATE` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `SECTION_ID` int(11) not null,
  `ITEM` varchar(72) NOT NULL,
  `STATUS` varchar(72) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

CREATE TABLE IF NOT EXISTS `SERVER_PERFORMANCE` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `RUN_ID` varchar(12),
  `TICK` timestamp NOT NULL DEFAULT current_timestamp(),
  `HOSTNAME` varchar(128) DEFAULT NULL,
  `REDO_LOG_OCCUPANCY_PCT` decimal(8,2) DEFAULT NULL,
  `THREADS_CONNECTED` int(11) DEFAULT NULL,
  `HANDLER_READ_RND_NEXT` bigint(20) DEFAULT NULL,
  `COM_SELECT` bigint(20) DEFAULT NULL,
  `COM_DML` bigint(20) DEFAULT NULL,
  `COM_XA_COMMIT` bigint(20) DEFAULT NULL,
  `SLOW_QUERIES` bigint(20) DEFAULT NULL,
  `LOCK_CURRENT_WAITS` bigint(20) DEFAULT NULL,
  `IBP_READS` bigint(20) DEFAULT NULL,
  `IBP_READ_REQUESTS` bigint(20) DEFAULT NULL,
  `MEMORY_USED` bigint(20) DEFAULT NULL,
  `BINLOG_COMMITS` bigint(20) DEFAULT NULL,
  `INNODB_BUFFER_POOL_DATA` bigint(20) DEFAULT NULL,
  `INNODB_DATA_WRITES` bigint(20) DEFAULT NULL,
  `INNODB_OS_LOG_WRITTEN` bigint(20) DEFAULT NULL,
  `INNODB_HISTORY_LIST_LENGTH` bigint(20) DEFAULT NULL,
  `COM_STMT_PREPARE` bigint(20) DEFAULT NULL,
  `COM_STMT_EXECUTE` bigint(20) DEFAULT NULL,
  `QCACHE_QUERIES_IN_CACHE` bigint(20) DEFAULT NULL,
  `QCACHE_FREE_MEMORY` bigint(20) DEFAULT NULL,
  `QCACHE_HITS` bigint(20) DEFAULT NULL,
  `QCACHE_INSERTS` bigint(20) DEFAULT NULL,
  `QCACHE_LOWMEM_PRUNES` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

CREATE TABLE IF NOT EXISTS `REVIEW_WARNINGS` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `FIRST_SEEN` timestamp NOT NULL DEFAULT current_timestamp(),
  `LAST_SEEN` timestamp NOT NULL DEFAULT current_timestamp(),
  `HOSTNAME` varchar(128) DEFAULT NULL,
  `RUN_ID` varchar(12) DEFAULT NULL,
  `ITEM` varchar(100) DEFAULT NULL,
  `STATUS` varchar(150) DEFAULT NULL,
  `INFO` longtext DEFAULT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UK_RUN_ID_ITEM` (`RUN_ID`,`ITEM`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

CREATE TABLE IF NOT EXISTS `SECTION_TITLES` (
  `SECTION_ID` int(11) NOT NULL,
  `TITLE` varchar(72) NOT NULL,
  PRIMARY KEY (`SECTION_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `ITERATION` (
  `ID` bigint(20) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

create table IF NOT EXISTS GLOBAL_VARIABLES ( 
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `VARIABLE_NAME` varchar(64) NOT NULL,
  `VARIABLE_VALUE` varchar(2048) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;


CREATE VIEW IF NOT EXISTS V_POTENTIAL_RAM_DEMAND as
WITH RAM_GLOBAL_VARIABLES AS (
SELECT
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='KEY_BUFFER_SIZE' limit 1) AS `KEY_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='QUERY_CACHE_SIZE' limit 1)AS `QUERY_CACHE_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='INNODB_BUFFER_POOL_SIZE' limit 1) AS `INNODB_BUFFER_POOL_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='INNODB_LOG_BUFFER_SIZE' limit 1) AS `INNODB_LOG_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='MAX_CONNECTIONS' limit 1) AS `MAX_CONNECTIONS`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='READ_BUFFER_SIZE' limit 1) AS `READ_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='READ_RND_BUFFER_SIZE' limit 1) AS `READ_RND_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='SORT_BUFFER_SIZE' limit 1) AS `SORT_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='JOIN_BUFFER_SIZE' limit 1) AS `JOIN_BUFFER_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='BINLOG_CACHE_SIZE' limit 1) AS `BINLOG_CACHE_SIZE`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='THREAD_STACK' limit 1) AS `THREAD_STACK`,
(select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME='TMP_TABLE_SIZE' limit 1) AS `TMP_TABLE_SIZE`)
 SELECT ( KEY_BUFFER_SIZE
+ QUERY_CACHE_SIZE
+ INNODB_BUFFER_POOL_SIZE
+ INNODB_LOG_BUFFER_SIZE
+ MAX_CONNECTIONS * ( 
    READ_BUFFER_SIZE
    + READ_RND_BUFFER_SIZE
    + SORT_BUFFER_SIZE
    + JOIN_BUFFER_SIZE
    + BINLOG_CACHE_SIZE
    + THREAD_STACK
    + TMP_TABLE_SIZE )
) AS MAX_RAM_USAGE FROM RAM_GLOBAL_VARIABLES;

CREATE VIEW IF NOT EXISTS V_SERVER_PERFORMANCE_PER_MIN as
select ID, RUN_ID, TICK, HOSTNAME, REDO_LOG_OCCUPANCY_PCT, THREADS_CONNECTED, 
LOCK_CURRENT_WAITS, MEMORY_USED, INNODB_BUFFER_POOL_DATA,
HANDLER_READ_RND_NEXT - (LAG(HANDLER_READ_RND_NEXT,1) OVER (ORDER BY ID)) as RND_NEXT_PER_MIN,
COM_SELECT - (LAG(COM_SELECT,1) OVER (ORDER BY ID)) as COM_SELECT_PER_MIN,
COM_DML - (LAG(COM_DML,1) OVER (ORDER BY ID)) as COM_DML_PER_MIN,
COM_XA_COMMIT - (LAG(COM_XA_COMMIT,1) OVER (ORDER BY ID)) as COM_XA_COMMIT_PER_MIN,
SLOW_QUERIES - (LAG(SLOW_QUERIES,1) OVER (ORDER BY ID)) as SLOW_QUERIES_PER_MIN,
IBP_READS - (LAG(IBP_READS,1) OVER (ORDER BY ID)) as IBP_READS_PER_MIN,
IBP_READ_REQUESTS - (LAG(IBP_READ_REQUESTS,1) OVER (ORDER BY ID)) as IBP_READ_REQUESTS_PER_MIN,
BINLOG_COMMITS - (LAG(BINLOG_COMMITS,1) OVER (ORDER BY ID)) as BINLOG_COMMITS_PER_MIN,
INNODB_DATA_WRITES - (LAG(INNODB_DATA_WRITES,1) OVER (ORDER BY ID)) as DATA_WRITES_PER_MIN,
INNODB_OS_LOG_WRITTEN - (LAG(INNODB_OS_LOG_WRITTEN,1) OVER (ORDER BY ID)) as OS_LOG_WRITTEN_PER_MIN,
INNODB_HISTORY_LIST_LENGTH,
COM_STMT_PREPARE - (LAG(COM_STMT_PREPARE,1) OVER (ORDER BY ID)) as COM_STMT_PREPARE_PER_MIN,
COM_STMT_EXECUTE - (LAG(COM_STMT_EXECUTE,1) OVER (ORDER BY ID)) as COM_STMT_EXECUTE_PER_MIN,
QCACHE_QUERIES_IN_CACHE, 
QCACHE_FREE_MEMORY,
QCACHE_HITS - (LAG(QCACHE_HITS,1) OVER (ORDER BY ID)) as QCACHE_HITS_PER_MIN,
QCACHE_INSERTS - (LAG(QCACHE_INSERTS,1) OVER (ORDER BY ID)) as QCACHE_INSERTS_PER_MIN,
QCACHE_LOWMEM_PRUNES - (LAG(QCACHE_LOWMEM_PRUNES,1) OVER (ORDER BY ID)) as QCACHE_LOWMEM_PRUNES_PER_MIN
from SERVER_PERFORMANCE
where RUN_ID = (select RUN_ID from CURRENT_RUN where ID = 1 limit 1);

create view IF NOT EXISTS V_SERVER_STATE as
select A.ID as ID, B.TITLE as SECTION, A.ITEM as ITEM, 
  if(A.STATUS REGEXP '^-?[0-9]+$' = 1,format(A.STATUS,0),A.STATUS) as STATUS
from SERVER_STATE A inner join SECTION_TITLES B 
ON A.SECTION_ID=B.SECTION_ID;

CREATE TABLE IF NOT EXISTS `GALERA_PERFORMANCE` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `RUN_ID` varchar(12),
  `TICK` timestamp NOT NULL DEFAULT current_timestamp(),
  `HOSTNAME` varchar(128) DEFAULT NULL,
  `WSREP_APPLIER_THREAD_COUNT` bigint(20) DEFAULT NULL,
  `WSREP_APPLY_OOOE` decimal(20,10) DEFAULT NULL,
  `WSREP_APPLY_OOOL` decimal(20,10) DEFAULT NULL,
  `WSREP_APPLY_WAITS` bigint(20) DEFAULT NULL,
  `WSREP_APPLY_WINDOW` decimal(20,10) DEFAULT NULL,
  `WSREP_CAUSAL_READS` bigint(20) DEFAULT NULL,
  `WSREP_CERT_DEPS_DISTANCE` decimal(20,10) DEFAULT NULL,
  `WSREP_CERT_INDEX_SIZE` bigint(20) DEFAULT NULL,
  `WSREP_CERT_INTERVAL` decimal(20,10) DEFAULT NULL,
  `WSREP_DESYNC_COUNT` bigint(20) DEFAULT NULL,
  `WSREP_EVS_DELAYED` varchar(256) DEFAULT NULL,
  `WSREP_EVS_EVICT_LIST` varchar(256) DEFAULT NULL,
  `WSREP_EVS_REPL_LATENCY` varchar(256) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_ACTIVE` varchar(20) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_PAUSED` decimal(20,10) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_PAUSED_NS` bigint(20) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_RECV` bigint(20) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_REQUESTED` varchar(20) DEFAULT NULL,
  `WSREP_FLOW_CONTROL_SENT` bigint(20) DEFAULT NULL,
  `WSREP_LAST_COMMITTED` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_BF_ABORTS` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_CACHED_DOWNTO` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_CERT_FAILURES` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_COMMITS` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_INDEX` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_RECV_QUEUE` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_RECV_QUEUE_AVG` decimal(20,10) DEFAULT NULL,
  `WSREP_LOCAL_RECV_QUEUE_MAX` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_RECV_QUEUE_MIN` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_REPLAYS` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_SEND_QUEUE` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_SEND_QUEUE_AVG` decimal(20,10) DEFAULT NULL,
  `WSREP_LOCAL_SEND_QUEUE_MAX` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_SEND_QUEUE_MIN` bigint(20) DEFAULT NULL,
  `WSREP_LOCAL_STATE_COMMENT` varchar(50) DEFAULT NULL,
  `WSREP_OPEN_CONNECTIONS` bigint(20) DEFAULT NULL,
  `WSREP_OPEN_TRANSACTIONS` bigint(20) DEFAULT NULL,
  `WSREP_RECEIVED` bigint(20) DEFAULT NULL,
  `WSREP_RECEIVED_BYTES` bigint(20) DEFAULT NULL,
  `WSREP_REPLICATED` bigint(20) DEFAULT NULL,
  `WSREP_REPLICATED_BYTES` bigint(20) DEFAULT NULL,
  `WSREP_REPL_DATA_BYTES` bigint(20) DEFAULT NULL,
  `WSREP_REPL_KEYS` bigint(20) DEFAULT NULL,
  `WSREP_REPL_KEYS_BYTES` bigint(20) DEFAULT NULL,
  `WSREP_REPL_OTHER_BYTES` bigint(20) DEFAULT NULL,
  `WSREP_ROLLBACKER_THREAD_COUNT` bigint(20) DEFAULT NULL,
  `WSREP_THREAD_COUNT` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

create view IF NOT EXISTS `V_GALERA_PERFORMANCE_PER_MIN` as
SELECT ID, RUN_ID, TICK, HOSTNAME,
WSREP_FLOW_CONTROL_PAUSED_NS - (LAG(WSREP_FLOW_CONTROL_PAUSED_NS,1) OVER (ORDER BY ID)) as WSREP_FLOW_CONTROL_PAUSED_NS_PER_MIN,
WSREP_FLOW_CONTROL_RECV - (LAG(WSREP_FLOW_CONTROL_RECV,1) OVER (ORDER BY ID)) as WSREP_FLOW_CONTROL_RECV_PER_MIN,
WSREP_FLOW_CONTROL_SENT - (LAG(WSREP_FLOW_CONTROL_SENT,1) OVER (ORDER BY ID)) as WSREP_FLOW_CONTROL_SENT_PER_MIN,
WSREP_LAST_COMMITTED - (LAG(WSREP_LAST_COMMITTED,1) OVER (ORDER BY ID)) as WSREP_LAST_COMMITTED_PER_MIN,
WSREP_LOCAL_COMMITS - (LAG(WSREP_LOCAL_COMMITS,1) OVER (ORDER BY ID)) as WSREP_LOCAL_COMMITS_PER_MIN,
WSREP_RECEIVED - (LAG(WSREP_RECEIVED,1) OVER (ORDER BY ID)) as WSREP_RECEIVED_PER_MIN,
WSREP_RECEIVED_BYTES - (LAG(WSREP_RECEIVED_BYTES,1) OVER (ORDER BY ID)) as WSREP_RECEIVED_BYTES_PER_MIN,
WSREP_REPLICATED - (LAG(WSREP_REPLICATED,1) OVER (ORDER BY ID)) as WSREP_REPLICATED_PER_MIN,
WSREP_REPLICATED_BYTES - (LAG(WSREP_REPLICATED_BYTES,1) OVER (ORDER BY ID)) as WSREP_REPLICATED_BYTES_PER_MIN,
WSREP_REPL_DATA_BYTES - (LAG(WSREP_REPL_DATA_BYTES,1) OVER (ORDER BY ID)) as WSREP_REPL_DATA_BYTES_PER_MIN,
WSREP_REPL_KEYS - (LAG(WSREP_REPL_KEYS,1) OVER (ORDER BY ID)) as WSREP_REPL_KEYS_PER_MIN,
WSREP_REPL_KEYS_BYTES - (LAG(WSREP_REPL_KEYS_BYTES,1) OVER (ORDER BY ID)) as WSREP_REPL_KEYS_BYTES_PER_MIN
from `GALERA_PERFORMANCE`
where RUN_ID = (select RUN_ID from CURRENT_RUN where ID = 1 limit 1);

CREATE TABLE IF NOT EXISTS `TABLE_KEY_COUNTS` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `TABLE_SCHEMA` VARCHAR(64) DEFAULT NULL,
  `TABLE_NAME` VARCHAR(64) DEFAULT NULL,
  `ENGINE` VARCHAR(64) DEFAULT NULL,
  `PRIMARY_KEY_COUNT` INTEGER(11) DEFAULT NULL,
  `UNIQUE_KEY_COUNT` INTEGER(11) DEFAULT NULL,
  `NON_UNIQUE_KEY_COUNT` INTEGER(11) DEFAULT NULL,
  `ROW_FORMAT` VARCHAR(32) DEFAULT NULL,
  `TABLE_ROWS` BIGINT(21) DEFAULT NULL,
  `AVG_ROW_LENGTH` BIGINT(21) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

create view IF NOT EXISTS `V_TABLE_KEY_COUNTS` as
SELECT `TABLE_SCHEMA`, `TABLE_NAME`, `PRIMARY_KEY_COUNT` as PKs,
        `UNIQUE_KEY_COUNT` as UKs, `NON_UNIQUE_KEY_COUNT` as NON_UKs, 
        `ROW_FORMAT`, `TABLE_ROWS`, `AVG_ROW_LENGTH`, 
        (`TABLE_ROWS` * `AVG_ROW_LENGTH`) AS `TOTAL_ROW_BYTES`, `ENGINE`
from TABLE_KEY_COUNTS;


-------------------------------------------------------------------------------------------------------
-- select * from V_EXPECTED_RAM_DEMAND to estimate the expected RAM that will be used as the number of 
-- connections rises. The formula is:
-- EXPECTED_WORKING_MEMORY = maximum Innodb_buffer_pool_bytes_data from STATUS 
--                           + KEY_BUFFER_SIZE + QUERY_CACHE_SIZE + INNODB_LOG_BUFFER_SIZE
-- EXPECTED_MEMORY_PER_SESSION = maximum MEMORY_USED / THREADS_CONNECTED from STATUS
-- SESSION_COUNT = an increasing sequence from 50 to 2000 (edit the last line to narrow the scope)
-- EXPECTED_DEMAND_BYTES = EXPECTED_WORKING_MEMORY + (EXPECTED_MEMORY_PER_SESSION * SESSION_COUNT)
-- KEEP IN MIND: The estimate will prove most accurate when performance data was collected on an
-- instance with many active sessions.
-------------------------------------------------------------------------------------------------------
create view IF NOT EXISTS `V_EXPECTED_RAM_DEMAND` as
WITH EXPECTED_MEMORY_USE AS (
SELECT * FROM
(SELECT SUM(V) AS `EXPECTED_WORKING_MEMORY` FROM (
SELECT VARIABLE_VALUE AS `V` FROM GLOBAL_VARIABLES 
WHERE VARIABLE_NAME IN ('KEY_BUFFER_SIZE','QUERY_CACHE_SIZE','INNODB_LOG_BUFFER_SIZE')
UNION ALL 
SELECT  max(INNODB_BUFFER_POOL_DATA) from V_SERVER_PERFORMANCE_PER_MIN
) AS x ) AS `EXPECTED_WORKING_MEMORY`,
(SELECT   round(max(MEMORY_USED/THREADS_CONNECTED)) AS `EXPECTED_MEMORY_PER_SESSION`
from V_SERVER_PERFORMANCE_PER_MIN)  AS `EXPECTED_MEMORY_PER_SESSION`)
SELECT EXPECTED_WORKING_MEMORY, EXPECTED_MEMORY_PER_SESSION, seq AS `SESSION_COUNT`, 
EXPECTED_WORKING_MEMORY + (EXPECTED_MEMORY_PER_SESSION * seq)  AS `EXPECTED_DEMAND_BYTES`,
ROUND((EXPECTED_WORKING_MEMORY + (EXPECTED_MEMORY_PER_SESSION * seq))/1024/1024)  AS `EXPECTED_DEMAND_MB`,
ROUND((EXPECTED_WORKING_MEMORY + (EXPECTED_MEMORY_PER_SESSION * seq))/1024/1024/1024)  AS `EXPECTED_DEMAND_GB`
FROM EXPECTED_MEMORY_USE
JOIN seq_50_to_2000;

CREATE VIEW `V_INNODB_REDO_STATUS` AS
WITH STS
AS (
    SELECT (
            select max(REDO_LOG_OCCUPANCY_PCT) from SERVER_PERFORMANCE
            ) AS MAX_REDO_OCCUPANCY_PCT
        ,(
            SELECT VARIABLE_VALUE
            FROM GLOBAL_VARIABLES
            WHERE VARIABLE_NAME = 'INNODB_LOG_FILE_SIZE'
            ) AS INNODB_LOG_FILE_SIZE
        ,(        
            SELECT VARIABLE_VALUE
            FROM GLOBAL_VARIABLES
            WHERE VARIABLE_NAME = 'INNODB_MAX_DIRTY_PAGES_PCT_LWM'
            ) AS INNODB_MAX_DIRTY_PAGES_PCT_LWM
        ,(
            SELECT VARIABLE_VALUE
            FROM GLOBAL_VARIABLES
            WHERE VARIABLE_NAME = 'INNODB_MAX_DIRTY_PAGES_PCT'
            ) AS INNODB_MAX_DIRTY_PAGES_PCT
    )
SELECT MAX_REDO_OCCUPANCY_PCT, 
INNODB_LOG_FILE_SIZE/1024/1024 as INNODB_LOG_FILE_MB,
INNODB_MAX_DIRTY_PAGES_PCT_LWM, INNODB_MAX_DIRTY_PAGES_PCT
FROM STS;

delimiter //
begin not atomic
if @DO_NOTHING !='YES' THEN
  INSERT INTO CURRENT_RUN (RUN_ID) values (@RUNID)
  ON DUPLICATE KEY UPDATE `RUN_ID`=@RUNID, `RUN_START`=now(), RUN_END=NULL, STATUS='RUNNING', STATS_COLLECTED=0;
  truncate table `SECTION_TITLES`;
  INSERT INTO `SECTION_TITLES` VALUES (1,'SERVER'),(2,'TOPOLOGY'),(3,'SCHEMAS'),(4,'PERFORMANCE'),(5,'GLOBALS'),(6,'WARNINGS'),(7,'GALERA');
  truncate table ITERATION;
  INSERT INTO `ITERATION` (`ID`) VALUES (@TIMES_TO_COLLECT_PERF_STATS);
  select ID into @REMAINING from ITERATION where 1=1 limit 1;
  truncate table `GLOBAL_VARIABLES`;
  insert into GLOBAL_VARIABLES (VARIABLE_NAME,VARIABLE_VALUE) 
  select * from information_schema.GLOBAL_VARIABLES order by VARIABLE_NAME asc;
  truncate table `TABLE_KEY_COUNTS`;
  insert into `TABLE_KEY_COUNTS` (`TABLE_SCHEMA`,`TABLE_NAME`,`ENGINE`,`PRIMARY_KEY_COUNT`,`UNIQUE_KEY_COUNT`,`NON_UNIQUE_KEY_COUNT`,`ROW_FORMAT`,`TABLE_ROWS`,`AVG_ROW_LENGTH`)
    SELECT C.`TABLE_SCHEMA`, C.`TABLE_NAME`, T.`ENGINE`,
    IF(SUM(case when C.COLUMN_KEY = 'PRI' then 1 else 0 END)>=1,1,0) AS `PRIMARY_KEY_COUNT`,
    SUM(case when C.COLUMN_KEY = 'UNI' then 1 else 0 END) AS `UNIQUE_KEY_COUNT`,
    SUM(case when C.COLUMN_KEY = 'MUL' then 1 else 0 END) AS `NON_UNIQUE_KEY_COUNT`,
    T.`ROW_FORMAT`, T.`TABLE_ROWS`, T.`AVG_ROW_LENGTH`
    FROM information_schema.`COLUMNS` C
    INNER JOIN information_schema.`TABLES` T
    ON (C.`TABLE_SCHEMA`=T.`TABLE_SCHEMA` AND C.`TABLE_NAME`=T.`TABLE_NAME`)
    WHERE C.`TABLE_SCHEMA` NOT IN ('information_schema','performance_schema','sys','mysql','mariadb_review')
    AND T.TABLE_TYPE='BASE TABLE'
    AND T.`ENGINE` != 'Columnstore'
    GROUP BY C.`TABLE_SCHEMA`, C.`TABLE_NAME`
    ORDER BY TABLE_SCHEMA, TABLE_NAME;
else
  set @REMAINING=0;
end if;
end;
//

delimiter ;

WITH REVIEW_SCHEMA_OBJECTS as (
SELECT
(select count(*) from information_schema.TABLES where TABLE_SCHEMA='mariadb_review' and TABLE_TYPE='BASE TABLE') as BASE_TABLES,
(select count(*) from information_schema.TABLES where TABLE_SCHEMA='mariadb_review' and TABLE_TYPE='VIEW') as VIEWS)
select concat('Schema mariadb_review exists with ',BASE_TABLES,' base tables and ',VIEWS,' views.') as `NOTE` from REVIEW_SCHEMA_OBJECTS;

delimiter //

begin not atomic
if @DO_NOTHING = 'YES' then
 select concat('Doing nothing.') as `NOTE`;
else

select VARIABLE_VALUE into @QUERY_CACHE_ENABLED 
from information_schema.GLOBAL_VARIABLES 
where VARIABLE_NAME='QUERY_CACHE_TYPE';

select VARIABLE_VALUE into @QUERY_CACHE_SIZE
from information_schema.GLOBAL_VARIABLES 
where VARIABLE_NAME='QUERY_CACHE_SIZE';

if @PRINCIPAL_VERSION = 10 AND @POINT_VERSION < 5 then
  select VARIABLE_VALUE into @LOG_FILE_SIZE 
    from information_schema.global_variables 
    where VARIABLE_NAME='INNODB_LOG_FILE_SIZE';
  select VARIABLE_VALUE into @LOG_FILES_IN_GROUP 
    from information_schema.global_variables 
    where VARIABLE_NAME='INNODB_LOG_FILES_IN_GROUP';
  set @LOG_FILE_CAPACITY=(@LOG_FILES_IN_GROUP * @LOG_FILE_SIZE);
else
  select VARIABLE_VALUE into @LOG_FILE_CAPACITY 
    from information_schema.global_variables 
    where VARIABLE_NAME='INNODB_LOG_FILE_SIZE';
end if;

/* TOPOLOGY */

select if(VARIABLE_VALUE>0,'YES','NO') into @IS_PRIMARY
  from information_schema.global_status 
  where VARIABLE_NAME='SLAVES_CONNECTED';
  
select if(sum(VARIABLE_VALUE)>0,'YES','NO') into @IS_REPLICA
  from information_schema.global_status 
  where VARIABLE_NAME in ('SLAVE_RECEIVED_HEARTBEATS','RPL_SEMI_SYNC_SLAVE_SEND_ACK','SLAVES_RUNNING');
  
select if(VARIABLE_VALUE>0,'YES','NO') into @REPLICA_RUNNING 
  from information_schema.global_status 
  where VARIABLE_NAME='SLAVES_RUNNING';

if @IS_REPLICA = 'YES' THEN
  select VARIABLE_VALUE into @SEMI_SYNC_SLAVE 
  from information_schema.global_status 
  where VARIABLE_NAME='RPL_SEMI_SYNC_SLAVE_STATUS';
end if;

if @IS_PRIMARY = 'YES' THEN
  select VARIABLE_VALUE into @SEMI_SYNC_MASTER 
  from information_schema.global_status 
  where VARIABLE_NAME='RPL_SEMI_SYNC_MASTER_STATUS'; 
end if;

/* Multi-threaded slave? */
if @IS_REPLICA = 'YES' THEN
  select VARIABLE_VALUE into @CONFIGURED_SLAVE_WORKERS
  from information_schema.global_variables 
  where VARIABLE_NAME = 'SLAVE_PARALLEL_THREADS';
  --
  select count(*) into @RUNNING_SLAVE_WORKERS
  from information_schema.processlist 
  where COMMAND='Slave_worker';
end if;

/* GALERA */
select if(VARIABLE_VALUE > 0,'YES','NO') into @IS_GALERA 
  from information_schema.global_status 
  where VARIABLE_NAME='WSREP_THREAD_COUNT';
  
if @IS_GALERA = 'YES' THEN
  select VARIABLE_VALUE into @GALERA_CLUSTER_SIZE
  from information_schema.global_status 
  where VARIABLE_NAME='WSREP_CLUSTER_SIZE';
end if;

/* NOTIFY IF LOG_BIN IS OFF */
select VARIABLE_VALUE into @BINARY_LOGGING 
from information_schema.GLOBAL_VARIABLES 
where variable_name='LOG_BIN';

/* SECTION ID 1 SERVER QUALITIES */
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'SCRIPT VERSION',@MARIADB_REVIEW_VERSION);
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'REVIEW STARTS',now());
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'HOSTNAME',@@hostname);

select VARIABLE_VALUE into @DB_UPTIME 
from information_schema.global_status 
where VARIABLE_NAME='UPTIME';

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'DATABASE UPTIME',concat('Since ',date_format(now() - interval @DB_UPTIME second,'%d-%b-%Y %H:%i:%S')));

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'CURRENT USER',current_user());

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'SOFTWARE VERSION',version());
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'DATADIR', @@datadir);
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 1, 
if(
  sum(DATA_LENGTH + INDEX_LENGTH + DATA_FREE) < @GB_THRESHOLD,
  'ESTIMATED DATA FILES MB',
  'ESTIMATED DATA FILES GB'
  ),
if(
  sum(DATA_LENGTH + INDEX_LENGTH + DATA_FREE) < @GB_THRESHOLD,
    concat(format(sum(DATA_LENGTH + INDEX_LENGTH + DATA_FREE)/1024/1024,2),'M'),  
    concat(format(sum(DATA_LENGTH + INDEX_LENGTH + DATA_FREE)/1024/1024/1024,2),'G')
  )
from information_schema.TABLES
where TABLE_TYPE != 'VIEW' 
and DATA_LENGTH is not null and INDEX_LENGTH is not null and DATA_FREE is not null;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 1, 
  if(@LOG_FILE_CAPACITY < @GB_THRESHOLD,
    'INNODB REDO LOG CAPACITY MB', 
    'INNODB REDO LOG CAPACITY GB'
    ),
  if(@LOG_FILE_CAPACITY < @GB_THRESHOLD,
    concat(format(@LOG_FILE_CAPACITY /1024/1024,2),'M'),
    concat(format(@LOG_FILE_CAPACITY /1024/1024/1024,2),'G')
    );

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 1, 
  if(`MAX_RAM_USAGE` < @GB_THRESHOLD,
    'MAX POTENTIAL MEMORY DEMAND MB', 
    'MAX POTENTIAL MEMORY DEMAND GB'
    ),
  if(`MAX_RAM_USAGE` < @GB_THRESHOLD,
    concat(format(`MAX_RAM_USAGE`/1024/1024,2),'M'),
    concat(format(`MAX_RAM_USAGE`/1024/1024/1024,2),'G')
    )
    from V_POTENTIAL_RAM_DEMAND 
where MAX_RAM_USAGE is not null limit 1;

/* Is Audit Plugin installed? */
select PLUGIN_LIBRARY into @AUDIT_PLUGIN from information_schema.plugins where PLUGIN_NAME='SERVER_AUDIT';
if @AUDIT_PLUGIN='server_audit.so' then -- MariaDB Community audit
  select if(length(VARIABLE_VALUE)=0,0,
  (LENGTH(VARIABLE_VALUE) - LENGTH(REPLACE(VARIABLE_VALUE, ',', '')) + 1)) as RULE_COUNT into @AUDIT_RULE_COUNT
  from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='SERVER_AUDIT_EVENTS';

  if @AUDIT_RULE_COUNT is null then set @AUDIT_RULE_COUNT = 0; end if; -- in theory, cannot happen. Just in case.

  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 1 as `SECTION_ID`, 'AUDIT PLUGIN INSTALLED' as `ITEM`,
    concat(format(@AUDIT_RULE_COUNT,0), if(@AUDIT_RULE_COUNT=1,' event audited',' events audited')) as `STATUS`
    from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='SERVER_AUDIT_EVENTS';
end if;

if @AUDIT_PLUGIN='server_audit2.so' then -- MariaDB Enterprise Audit
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 1 as `SECTION_ID`, 'ENTERPRISE AUDIT PLUGIN INSTALLED' as `ITEM`,
  concat(format(count(*),0),if(count(*)=1,' rule',' rules'),' in mysql.server_audit_filters') as `STATUS`
  from mysql.server_audit_filters limit 1;
end if;
/* Is Audit Plugin installed? */

/* SECTION 2 REPLICATION AND TOPOLOGY */

if @IS_GALERA ='YES' THEN
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'IS MEMBER OF GALERA CLUSTER', @IS_GALERA;
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'GALERA CLUSTER SIZE', @GALERA_CLUSTER_SIZE;
end if;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 2, 'IS A PRIMARY', @IS_PRIMARY;
if @IS_PRIMARY = 'YES' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'SEMISYNCHRONOUS PRIMARY',@SEMI_SYNC_MASTER;
end if;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 2, 'IS A REPLICA', @IS_REPLICA;
if @IS_REPLICA = 'YES' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'SLAVE IS RUNNING',@REPLICA_RUNNING;
  if @REPLICA_RUNNING='YES' then
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'SEMISYNCHRONOUS REPLICA',@SEMI_SYNC_SLAVE;
  ELSE
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'SEMISYNCHRONOUS REPLICA', if(VARIABLE_VALUE='ON','ENABLED','DISABLED') 
    from information_schema.global_variables where variable_name='RPL_SEMI_SYNC_SLAVE_ENABLED';
  end if;

  if @CONFIGURED_SLAVE_WORKERS > 0 THEN
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'CONFIGURED SLAVE WORKERS',@CONFIGURED_SLAVE_WORKERS;
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'RUNNING SLAVE WORKERS',@RUNNING_SLAVE_WORKERS;
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 5, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME='SLAVE_PARALLEL_MODE';
  ELSE
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
    (2,'PARALLEL REPLICATION','OFF');
  end if;
end if;

/* SECTION 5 GLOBALS STARTING WITH THOSE RELATED TO TOPOLOGY & REPLICATION */

if @BINARY_LOGGING = 'ON' AND @IS_REPLICA = 'YES' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 5, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME = 'LOG_SLAVE_UPDATES';
end if;

if @BINARY_LOGGING = 'ON' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 5, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME='BINLOG_FORMAT';
else
 insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
 select 5, 'LOG_BIN (BINARY LOGGING)','OFF';
end if;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 5, 
if(VARIABLE_VALUE < @GB_THRESHOLD,
  concat(VARIABLE_NAME,' (MB)'), 
  concat(VARIABLE_NAME,' (GB)')
  ),  
if(VARIABLE_VALUE < @GB_THRESHOLD,
  concat(format(VARIABLE_VALUE/1024/1024,2),'M'),
  concat(format(VARIABLE_VALUE/1024/1024/1024,2),'G')
  )
from GLOBAL_VARIABLES where VARIABLE_NAME='INNODB_BUFFER_POOL_SIZE';

select VARIABLE_VALUE into @THREAD_HAND from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='THREAD_HANDLING';
if @THREAD_HAND !='one-thread-per-connection' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 5, VARIABLE_NAME, VARIABLE_VALUE from information_schema.GLOBAL_VARIABLES 
  where VARIABLE_NAME IN ('THREAD_HANDLING','THREAD_POOL_SIZE') order by VARIABLE_NAME asc;
end if;

select VARIABLE_VALUE into @GEN_LOG from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='GENERAL_LOG';
if @GEN_LOG != 'OFF' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 5, VARIABLE_NAME, VARIABLE_VALUE from information_schema.GLOBAL_VARIABLES 
  where VARIABLE_NAME IN ('GENERAL_LOG','GENERAL_LOG_FILE','LOG_OUTPUT') order by VARIABLE_NAME asc;
end if;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 5, VARIABLE_NAME as `ITEM`, concat('Not set') as `STATUS` from information_schema.GLOBAL_VARIABLES 
where VARIABLE_NAME='LOG_ERROR' 
and (VARIABLE_VALUE='' or VARIABLE_VALUE is null);



/* SECTION 3 USER SCHEMAS AND TABLES */
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED SCHEMAS', count(*) from information_schema.schemata where SCHEMA_NAME not in
('information_schema','performance_schema','sys','mysql','mariadb_review') having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED BASE TABLES', count(*) from information_schema.tables where TABLE_SCHEMA not in
('information_schema','performance_schema','sys','mysql','mariadb_review') and TABLE_TYPE = 'BASE TABLE'
having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED SEQUENCES', count(*) from information_schema.tables where TABLE_SCHEMA not in
('information_schema','performance_schema','sys','mysql','mariadb_review') and TABLE_TYPE = 'SEQUENCE' 
having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED VIEWS', count(*) from information_schema.tables where TABLE_SCHEMA not in
('information_schema','performance_schema','sys','mysql','mariadb_review') and TABLE_TYPE = 'VIEW' 
having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED ROUTINES', count(*) from information_schema.routines where ROUTINE_SCHEMA not in
('information_schema','performance_schema','sys','mysql','mariadb_review') 
having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED PARTITIONED TABLES', count(distinct TABLE_SCHEMA,TABLE_NAME) as partitioned_table_count 
FROM information_schema.partitions 
WHERE PARTITION_NAME is not null
AND TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review') 
having count(distinct TABLE_SCHEMA,TABLE_NAME) > 0;
select VARIABLE_VALUE into @EVENT_SCHED from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='EVENT_SCHEDULER';
if @EVENT_SCHED = 'ON' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 3, 'USER CREATED EVENTS', count(*) from information_schema.EVENTS 
  WHERE EVENT_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review') 
  having count(*) > 0;
end if;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, concat('USER CREATED ',INDEX_TYPE,' INDEXES') as `ITEM`, count(*) as `STATUS`
from information_schema.`STATISTICS`
where INDEX_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
group by INDEX_TYPE 
having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED TRIGGERS', count(*) 
from information_schema.`TRIGGERS`
where TRIGGER_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'STORED GENERATED COLUMNS', count(*) 
from information_schema.`COLUMNS`
where TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
and EXTRA='STORED GENERATED' having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'VIRTUAL GENERATED COLUMNS', count(*) 
from information_schema.`COLUMNS`
where TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
and EXTRA='VIRTUAL GENERATED' having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, concat('TABLES ',ENGINE,' ENGINE'), count(*) from information_schema.tables 
where ENGINE is not null 
and TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
group by  ENGINE having count(*) > 0;
 
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3 as SECTION_ID, concat('TABLES INNODB ROW_FORMAT ',upper(row_format)) as ITEM, count(*) as STATUS
from information_schema.tables 
where engine='InnoDB' 
and TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
group by row_format
having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES WITH PAGE COMPRESSION', count(*) 
from information_schema.tables 
where CREATE_OPTIONS like '%PAGE_COMPRESSED%ON%'
having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLESPACES WITH DATA-AT-REST ENCRYPTION', count(NAME) 
from information_schema.INNODB_TABLESPACES_ENCRYPTION
having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'SYSTEM VERSIONED TABLES', count(*) 
from information_schema.tables where TABLE_TYPE='SYSTEM VERSIONED' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'ALT DATA DIR DEFINED TABLES', count(*) from information_schema.tables 
where CREATE_OPTIONS like '%DATA DIRECTORY%' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'ALT INDEX DIR DEFINED TABLES', count(*) from information_schema.tables 
where CREATE_OPTIONS like '%INDEX DIRECTORY%' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES WITHOUT PRIMARY KEY', COUNT(*) 
from TABLE_KEY_COUNTS where PRIMARY_KEY_COUNT=0;

/* SINGLE RUN WARNINGS FOR THINGS THAT ARE SOMEWHAT PERMANENT */
insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname,
substr(concat('ROW_FORMAT=COMPRESSED: ',TABLE_SCHEMA,'.',TABLE_NAME),1,100) as `ITEM`,
  if(DATA_LENGTH+INDEX_LENGTH+DATA_FREE < @GB_THRESHOLD,
    concat(format((DATA_LENGTH+INDEX_LENGTH+DATA_FREE)/1024/1024,0),'M on disk needs ',format(((DATA_LENGTH+INDEX_LENGTH+DATA_FREE)*3)/1024/1024,0),'M of buffer pool'),
    concat(format((DATA_LENGTH+INDEX_LENGTH+DATA_FREE)/1024/1024/1024,2),'G on disk needs ',format(((DATA_LENGTH+INDEX_LENGTH+DATA_FREE)*3)/1024/1024/1024,2),'G of buffer pool')
  ) as `STATUS`,
  concat('ROW_FORMAT compressed tables require additional pages of buffer pool memory. InnoDB tries to keep both compressed and uncompressed pages in the buffer pool.') as `INFO`
from information_schema.TABLES 
where TABLE_SCHEMA NOT IN ('information_schema','performance_schema','sys','mysql','mariadb_review') 
and ROW_FORMAT='Compressed'
and DATA_LENGTH+INDEX_LENGTH+DATA_FREE > @ROW_FORMAT_COMPRESSED_THRESHOLD
and DATA_LENGTH is not null and INDEX_LENGTH is not null and DATA_FREE is not null
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB';

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname,
concat('QUERY CACHE HITS IS LOW') as ITEM,
concat(format(VARIABLE_VALUE,0), if(VARIABLE_VALUE=1,' hit',' hits')) as `STATUS`, NULL as `INFO`
from information_schema.GLOBAL_STATUS
where VARIABLE_NAME='QCACHE_HITS'
and VARIABLE_VALUE < @LOW_QUERY_CACHE_HITS_THRESHOLD
and @QUERY_CACHE_ENABLED !='OFF'
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname,
substr(concat('LARGE DATAFILE, FEW ROWS: ', TABLE_SCHEMA,'.',TABLE_NAME),1,100) as `ITEM`,
concat(format(((DATA_LENGTH + INDEX_LENGTH + DATA_FREE) / 1024 / 1024),0),'M, ',format(TABLE_ROWS,0),if(TABLE_ROWS=1,' ROW',' ROWS')), NULL
from information_schema.tables
where TABLE_ROWS < @LARGE_EMPTY_LOW_ROWCOUNT
and (DATA_LENGTH + INDEX_LENGTH + DATA_FREE) > @LARGE_EMPTY_DATAFILE_THRESHOLD
and DATA_LENGTH is not null and INDEX_LENGTH is not null and DATA_FREE is not null
and TABLE_ROWS < @LARGE_EMPTY_LOW_ROWCOUNT
and TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
and TABLE_TYPE='BASE TABLE'
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
SELECT @RUNID,@@hostname,
substr(concat('LOW CARDIN IDX: ',A.TABLE_SCHEMA,'.',A.TABLE_NAME),1,100) as ITEM,
substr(concat('Index ',A.INDEX_NAME,': ',format(A.CARDINALITY,0),' unique values'),1,150) as STATUS, NULL
FROM information_schema.STATISTICS A 
INNER JOIN information_schema.TABLES B 
on (A.TABLE_SCHEMA=B.TABLE_SCHEMA and A.TABLE_NAME=B.TABLE_NAME) 
WHERE A.NON_UNIQUE != 0 
AND (A.CARDINALITY/B.TABLE_ROWS)*100 < @WARN_LOW_CARDINALITY_PCT
AND B.TABLE_ROWS >= @MIN_ROWS_TO_CHECK_INDEX_CARDINALITY
and A.TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
and B.TABLE_TYPE='BASE TABLE'
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname, 
if(count(*)=1, concat('THERE IS ',format(count(*),0),' MyISAM TABLE'),
               concat('THERE ARE ',format(count(*),0),' MyISAM TABLES')) as `ITEM`,
concat('MyISAM tables are not crash safe') as `STATUS`,
concat('MyISAM engine is non-transactional which means it does not support commit/rollback.') as `INFO`
from information_schema.tables 
where ENGINE='MyISAM'
and TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql','mariadb_review')
and TABLE_TYPE='BASE TABLE'
group by ENGINE 
having count(*) > 0;

if @IS_GALERA ='YES' then
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 
  concat(if(count(*)=1,'THERE IS ','THERE ARE '),count(*),' table',if(count(*)=1,'','s'),' ENGINE NOT InnoDB') as ITEM,
  concat('Galera only supports InnoDB tables') as STATUS,
  NULL as INFO
  from information_schema.TABLES 
  where ENGINE !='InnoDB'
  AND TABLE_SCHEMA NOT IN ('information_schema','performance_schema','sys','mysql','mariadb_review')
  AND TABLE_TYPE='BASE TABLE'
  having count(*) > 0
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
  
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname,
  substr(concat('NO PK: ', t.TABLE_SCHEMA,'.',t.TABLE_NAME),1,100) as `ITEM`,
  concat('Table must have a primary key for Galera'), NULL
  from TABLE_KEY_COUNTS t 
  where PRIMARY_KEY_COUNT=0
  AND t.`ENGINE` = 'InnoDB'  
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
else
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname,
  substr(concat('BIG TABLE NO PK: ', t.TABLE_SCHEMA,'.',t.TABLE_NAME),1,100) as `ITEM`,
  concat(format(t.TABLE_ROWS,0),if(t.TABLE_ROWS=1,' row',' rows')), NULL
  from TABLE_KEY_COUNTS t
  where `TABLE_ROWS` >= @MIN_ROWS_NO_PK_THRESHOLD
  and PRIMARY_KEY_COUNT=0 
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
end if;

/* END SINGLE RUN WARNINGS */

/* SECTION 4 PERFORMANCE */
if @TIMES_TO_COLLECT_PERF_STATS > 0 then

if @TIMES_TO_COLLECT_PERF_STATS = 1 then
  SIGNAL SQLSTATE '01000' 
  SET MESSAGE_TEXT="Set TIMES_TO_COLLECT_PERF_STATS to 2 or more in order to generate comparison values.", 
  MYSQL_ERRNO = 1000;
  show warnings;
end if;

select concat('Collecting Performance Data. This will take about ',format(@TIMES_TO_COLLECT_PERF_STATS,0), if(@TIMES_TO_COLLECT_PERF_STATS=1,' minute.', ' minutes.')) as NOTE;
set @PERFORMANCE_SAMPLES = 0;

COLLECT_PERFORMANCE_RUN: WHILE @REMAINING > 0 DO
update ITERATION set `ID`=`ID` - 1 where `ID` > 0; 

/* GOING TO START AT 0 SECONDS OF EACH MINUTE */
START_AT_0_SECS: WHILE cast(date_format(now(),'%S') as integer) > 0 DO
  DO SLEEP(0.1);
END WHILE START_AT_0_SECS;

SELECT VARIABLE_VALUE INTO @CHECKPOINT_AGE
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME='INNODB_CHECKPOINT_AGE';

SET @OCCUPANCY=format((@CHECKPOINT_AGE/@LOG_FILE_CAPACITY)*100,2);

SELECT VARIABLE_VALUE into @THREADS
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME='THREADS_CONNECTED';
 
SELECT VARIABLE_VALUE into @RND_NEXT
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='HANDLER_READ_RND_NEXT';

SELECT VARIABLE_VALUE INTO @COM_SEL
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='COM_SELECT';

SELECT SUM(VARIABLE_VALUE) into @COM_DML
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME IN ('COM_INSERT','COM_UPDATE','COM_DELETE');

SELECT VARIABLE_VALUE into @COM_XA
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME = 'Com_xa_commit';

SELECT VARIABLE_VALUE into @SLOW_Q
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME = 'Slow_queries';
  
SELECT VARIABLE_VALUE INTO @ROW_LOCK_CURRENT_WAITS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_ROW_LOCK_CURRENT_WAITS';

SELECT VARIABLE_VALUE INTO @IBP_READS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_BUFFER_POOL_READS';
  
SELECT VARIABLE_VALUE INTO @IBP_READ_REQS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_BUFFER_POOL_READ_REQUESTS';
  
SELECT VARIABLE_VALUE INTO @MEM_USED
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='MEMORY_USED';

SELECT VARIABLE_VALUE INTO @BUFFER_POOL_DATA
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_BUFFER_POOL_BYTES_DATA';

SELECT VARIABLE_VALUE INTO @BINLOG_TXNS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='BINLOG_COMMITS';
  
SELECT VARIABLE_VALUE INTO @DATA_WRITES
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_DATA_WRITES';

SELECT VARIABLE_VALUE INTO @OS_LOG_WRITTEN
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_OS_LOG_WRITTEN';
  
SELECT VARIABLE_VALUE INTO @STMT_PREPARE
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='COM_STMT_PREPARE';
  
SELECT VARIABLE_VALUE INTO @STMT_EXECUTE
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='COM_STMT_EXECUTE';

SELECT VARIABLE_VALUE INTO @QUERIES_IN_CACHE
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='QCACHE_QUERIES_IN_CACHE';

SELECT VARIABLE_VALUE INTO @QCACHE_FREE_MEM
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='QCACHE_FREE_MEMORY';

SELECT VARIABLE_VALUE INTO @CACHE_HITS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='QCACHE_HITS';
  
SELECT VARIABLE_VALUE INTO @CACHE_INSERTS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='QCACHE_INSERTS';
  
SELECT VARIABLE_VALUE INTO @LOWMEM_PRUNES
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='QCACHE_LOWMEM_PRUNES';
  
SELECT VARIABLE_VALUE INTO @HISTORY_LIST_LENGTH
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_HISTORY_LIST_LENGTH';
  
INSERT INTO `SERVER_PERFORMANCE` 
(RUN_ID,TICK,HOSTNAME,REDO_LOG_OCCUPANCY_PCT,THREADS_CONNECTED,HANDLER_READ_RND_NEXT,COM_SELECT,COM_DML,COM_XA_COMMIT,SLOW_QUERIES,LOCK_CURRENT_WAITS,IBP_READS,IBP_READ_REQUESTS,MEMORY_USED, INNODB_BUFFER_POOL_DATA, BINLOG_COMMITS, INNODB_DATA_WRITES, INNODB_OS_LOG_WRITTEN, COM_STMT_PREPARE, COM_STMT_EXECUTE,QCACHE_QUERIES_IN_CACHE,QCACHE_FREE_MEMORY,QCACHE_HITS,QCACHE_INSERTS,QCACHE_LOWMEM_PRUNES,INNODB_HISTORY_LIST_LENGTH)
SELECT @RUNID, now(), @@hostname, @OCCUPANCY, @THREADS, @RND_NEXT, @COM_SEL, @COM_DML, @COM_XA, @SLOW_Q, @ROW_LOCK_CURRENT_WAITS, @IBP_READS, @IBP_READ_REQS,@MEM_USED,@BUFFER_POOL_DATA,@BINLOG_TXNS,@DATA_WRITES,@OS_LOG_WRITTEN,@STMT_PREPARE,@STMT_EXECUTE,@QUERIES_IN_CACHE,@QCACHE_FREE_MEM,@CACHE_HITS,@CACHE_INSERTS,@LOWMEM_PRUNES,@HISTORY_LIST_LENGTH;

IF @IS_GALERA ='YES' then
INSERT INTO GALERA_PERFORMANCE (RUN_ID,TICK,HOSTNAME,WSREP_APPLIER_THREAD_COUNT,WSREP_APPLY_OOOE,WSREP_APPLY_OOOL,WSREP_APPLY_WAITS,WSREP_APPLY_WINDOW,WSREP_CAUSAL_READS,WSREP_CERT_DEPS_DISTANCE,WSREP_CERT_INDEX_SIZE,WSREP_CERT_INTERVAL,WSREP_DESYNC_COUNT,WSREP_EVS_DELAYED,WSREP_EVS_EVICT_LIST,WSREP_EVS_REPL_LATENCY,WSREP_FLOW_CONTROL_ACTIVE,WSREP_FLOW_CONTROL_PAUSED,WSREP_FLOW_CONTROL_PAUSED_NS,WSREP_FLOW_CONTROL_RECV,WSREP_FLOW_CONTROL_REQUESTED,WSREP_FLOW_CONTROL_SENT,WSREP_LAST_COMMITTED,WSREP_LOCAL_BF_ABORTS,WSREP_LOCAL_CACHED_DOWNTO,WSREP_LOCAL_CERT_FAILURES,WSREP_LOCAL_COMMITS,WSREP_LOCAL_INDEX,WSREP_LOCAL_RECV_QUEUE,WSREP_LOCAL_RECV_QUEUE_AVG,WSREP_LOCAL_RECV_QUEUE_MAX,WSREP_LOCAL_RECV_QUEUE_MIN,WSREP_LOCAL_REPLAYS,WSREP_LOCAL_SEND_QUEUE,WSREP_LOCAL_SEND_QUEUE_AVG,WSREP_LOCAL_SEND_QUEUE_MAX,WSREP_LOCAL_SEND_QUEUE_MIN,WSREP_LOCAL_STATE_COMMENT,WSREP_OPEN_CONNECTIONS,WSREP_OPEN_TRANSACTIONS,WSREP_RECEIVED,WSREP_RECEIVED_BYTES,WSREP_REPLICATED,WSREP_REPLICATED_BYTES,WSREP_REPL_DATA_BYTES,WSREP_REPL_KEYS,WSREP_REPL_KEYS_BYTES,WSREP_REPL_OTHER_BYTES,WSREP_ROLLBACKER_THREAD_COUNT,WSREP_THREAD_COUNT)
SELECT @RUNID, now(), @@hostname, 
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_APPLIER_THREAD_COUNT') AS `WSREP_APPLIER_THREAD_COUNT`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_APPLY_OOOE') AS `WSREP_APPLY_OOOE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_APPLY_OOOL') AS `WSREP_APPLY_OOOL`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_APPLY_WAITS') AS `WSREP_APPLY_WAITS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_APPLY_WINDOW') AS `WSREP_APPLY_WINDOW`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_CAUSAL_READS') AS `WSREP_CAUSAL_READS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_CERT_DEPS_DISTANCE') AS `WSREP_CERT_DEPS_DISTANCE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_CERT_INDEX_SIZE') AS `WSREP_CERT_INDEX_SIZE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_CERT_INTERVAL') AS `WSREP_CERT_INTERVAL`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_DESYNC_COUNT') AS `WSREP_DESYNC_COUNT`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_EVS_DELAYED') AS `WSREP_EVS_DELAYED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_EVS_EVICT_LIST') AS `WSREP_EVS_EVICT_LIST`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_EVS_REPL_LATENCY') AS `WSREP_EVS_REPL_LATENCY`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_ACTIVE') AS `WSREP_FLOW_CONTROL_ACTIVE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_PAUSED') AS `WSREP_FLOW_CONTROL_PAUSED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_PAUSED_NS') AS `WSREP_FLOW_CONTROL_PAUSED_NS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_RECV') AS `WSREP_FLOW_CONTROL_RECV`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_REQUESTED') AS `WSREP_FLOW_CONTROL_REQUESTED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_FLOW_CONTROL_SENT') AS `WSREP_FLOW_CONTROL_SENT`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LAST_COMMITTED') AS `WSREP_LAST_COMMITTED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_BF_ABORTS') AS `WSREP_LOCAL_BF_ABORTS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_CACHED_DOWNTO') AS `WSREP_LOCAL_CACHED_DOWNTO`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_CERT_FAILURES') AS `WSREP_LOCAL_CERT_FAILURES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_COMMITS') AS `WSREP_LOCAL_COMMITS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_INDEX') AS `WSREP_LOCAL_INDEX`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_RECV_QUEUE') AS `WSREP_LOCAL_RECV_QUEUE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_RECV_QUEUE_AVG') AS `WSREP_LOCAL_RECV_QUEUE_AVG`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_RECV_QUEUE_MAX') AS `WSREP_LOCAL_RECV_QUEUE_MAX`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_RECV_QUEUE_MIN') AS `WSREP_LOCAL_RECV_QUEUE_MIN`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_REPLAYS') AS `WSREP_LOCAL_REPLAYS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_SEND_QUEUE') AS `WSREP_LOCAL_SEND_QUEUE`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_SEND_QUEUE_AVG') AS `WSREP_LOCAL_SEND_QUEUE_AVG`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_SEND_QUEUE_MAX') AS `WSREP_LOCAL_SEND_QUEUE_MAX`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_SEND_QUEUE_MIN') AS `WSREP_LOCAL_SEND_QUEUE_MIN`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_LOCAL_STATE_COMMENT') AS `WSREP_LOCAL_STATE_COMMENT`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_OPEN_CONNECTIONS') AS `WSREP_OPEN_CONNECTIONS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_OPEN_TRANSACTIONS') AS `WSREP_OPEN_TRANSACTIONS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_RECEIVED') AS `WSREP_RECEIVED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_RECEIVED_BYTES') AS `WSREP_RECEIVED_BYTES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPLICATED') AS `WSREP_REPLICATED`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPLICATED_BYTES') AS `WSREP_REPLICATED_BYTES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPL_DATA_BYTES') AS `WSREP_REPL_DATA_BYTES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPL_KEYS') AS `WSREP_REPL_KEYS`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPL_KEYS_BYTES') AS `WSREP_REPL_KEYS_BYTES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_REPL_OTHER_BYTES') AS `WSREP_REPL_OTHER_BYTES`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_ROLLBACKER_THREAD_COUNT') AS `WSREP_ROLLBACKER_THREAD_COUNT`,
(SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS where VARIABLE_NAME='WSREP_THREAD_COUNT') AS `WSREP_THREAD_COUNT`
LIMIT 1;
end if;

/* POPULATE WARNINGS TABLE START */

if @REPLICA_RUNNING = 'YES' then
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 
  substr(concat('MULTI-ROW UPDATE FROM MASTER, NO INDEX, QUERY_ID: ',QUERY_ID),1,100),
  concat(`DB`,'.',SUBSTRING_INDEX(SUBSTRING_INDEX(`STATE`,'`',2),'`',-1)),`INFO`
  from information_schema.processlist
  where `USER` = 'system user' 
  and `COMMAND` in ('Slave_SQL','Slave_worker')
  and `STATE` like 'Update_rows_log_event::find_row(%) on table%' limit 1
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();

  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 
  substr(concat('MULTI-ROW DELETE FROM MASTER, NO INDEX, QUERY_ID: ',QUERY_ID),1,100),
  concat(`DB`,'.',SUBSTRING_INDEX(SUBSTRING_INDEX(`STATE`,'`',2),'`',-1)),`INFO`
  from information_schema.processlist
  where `USER` = 'system user' 
  and `COMMAND` in ('Slave_SQL','Slave_worker')
  and `STATE` like 'Delete_rows_log_event::find_row(%) on table%' limit 1
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
end if; -- @REPLICA_RUNNING = 'YES'

if @OCCUPANCY is not null and @OCCUPANCY >= @REDO_WARNING_PCT_THRESHOLD THEN
    insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO) VALUES 
    (@RUNID,@@hostname, 'REDO OCCUPANCY IS HIGH',concat(@OCCUPANCY,'%'), NULL)
    ON DUPLICATE KEY UPDATE 
    LAST_SEEN=now(),
    STATUS=if(REGEXP_SUBSTR(STATUS,"[0-9.]+") < @OCCUPANCY, concat(@OCCUPANCY,'%'), STATUS);
end if;

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname,
concat('LONG RUNNING TRX QUERY_ID: ',B.QUERY_ID) as ITEM,
if(B.USER='system user',concat(B.USER,', trx started ',date_format(A.trx_started,'%b %d %H:%i')),concat(B.USER,'@',SUBSTRING_INDEX(B.HOST,':',1),', trx started ',date_format(A.trx_started,'%b %d %H:%i'))) as STATUS,
trx_query as INFO
from information_schema.INNODB_TRX A
INNER JOIN information_schema.PROCESSLIST B on (A.trx_mysql_thread_id = B.ID)
WHERE A.trx_started < now() - interval @LONG_RUNNING_TRX_THRESHOLD_MINUTES minute
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
WITH `BLOCKERS` AS (
SELECT r.trx_id AS WAITING_TRX_ID, 
r.trx_mysql_thread_id AS WAITING_THREAD, 
pl1.USER AS WAITING_USER, pl1.HOST AS WAITING_HOST,
r.trx_query AS WAITING_QUERY,
b.trx_id AS BLOCKING_TRX_ID, 
pl2.USER AS BLOCKING_USER, pl2.HOST AS BLOCKING_HOST,
b.trx_mysql_thread_id AS BLOCKING_THREAD
FROM information_schema.innodb_lock_waits w
INNER JOIN information_schema.innodb_trx b
ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx AS r
ON r.trx_id = w.requesting_trx_id
INNER JOIN information_schema.processlist pl1
ON r.trx_mysql_thread_id = pl1.ID
INNER JOIN information_schema.processlist pl2
ON b.trx_mysql_thread_id =pl2.ID) 
SELECT @RUNID,@@hostname, 
substr(CONCAT(BLOCKING_USER,'@',SUBSTRING_INDEX(BLOCKING_HOST,':',1),' (PID:',BLOCKING_THREAD,') BLOCKING TXN'),1,100) AS `ITEM`,
substr(CONCAT(WAITING_USER,'@',SUBSTRING_INDEX(WAITING_HOST,':',1),' (PID:',WAITING_THREAD,') WAITING'),1,150) AS `STATUS`,
CONCAT('WAITING QUERY: ',WAITING_QUERY) AS `INFO`
FROM `BLOCKERS`
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

if @IS_GALERA ='YES' then
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 
  'GALERA FLOW CONTROL IS ACTIVE' as ITEM,
  'Verify that tables have required keys' as STATUS,
  NULL as `INFO`
  from information_schema.GLOBAL_STATUS 
  where VARIABLE_NAME='WSREP_FLOW_CONTROL_ACTIVE'
  and VARIABLE_VALUE='true'
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();

  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 
  substr(concat('LONG RUNNING TXN, QUERY_ID: ',QUERY_ID),1,100) as ITEM,
  substr(concat('USER: ',if(USER='system user',USER,concat('`',USER,'`@`',HOST,'`')),', TIME_MS: ',TIME_MS),1,150) as STATUS,
  `INFO` as INFO
  from information_schema.processlist
  where TIME_MS > @GALERA_LONG_RUNNING_TXN_MS
  and INFO is not null
  and STATE in ('Commit','Updating','Sending data')
  ON DUPLICATE KEY UPDATE 
  LAST_SEEN=now(),
  STATUS=substr(concat('USER: ',if(USER='system user',USER,concat('`',USER,'`@`',HOST,'`')),', TIME_MS: ',TIME_MS),1,150);

  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)  
  select @RUNID,@@hostname, 
  substr(concat('REPLICATING TXN NO INDEX, QUERY_ID: ',QUERY_ID),1,100) as ITEM,
  substr(concat(`DB`,'.',SUBSTRING_INDEX(SUBSTRING_INDEX(`STATE`,'`',2),'`',-1)),1,150) as `STATUS`,
  `INFO` as INFO
  from information_schema.processlist
  where `STATE` like '%rows_log_event::find_row(%) on table%'
  and USER='system user'
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
  
end if;

if @HISTORY_LIST_LENGTH >= @HISTORY_LIST_LENGTH_THRESHOLD then
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)  
  VALUES (@RUNID,@@hostname,'INNODB_HISTORY_LIST_LENGTH IS HIGH', @HISTORY_LIST_LENGTH, 'The total number of undo logs that contain modifications in the history list. If the InnoDB history list length grows too large, indicating a large number of old row versions, queries and database shutdowns become slower.')
  ON DUPLICATE KEY UPDATE LAST_SEEN=now(), STATUS=if(@HISTORY_LIST_LENGTH > cast(`status` as integer),@HISTORY_LIST_LENGTH,`status`);
end if;

 /* POPULATE WARNINGS TABLE END */

select concat('Performance statistics run number ',format((@TIMES_TO_COLLECT_PERF_STATS - @REMAINING)+1,0),' of ',format(@TIMES_TO_COLLECT_PERF_STATS,0),' completed.') as NOTE;

update CURRENT_RUN set STATS_COLLECTED=STATS_COLLECTED+1 where ID=1;

select ID into @REMAINING from ITERATION where 1=1 limit 1;
/* Ensure performance collections are 1 minute apart by sleeping for 55 seconds. */
if @REMAINING > 0 then do sleep(55); end if; 

set @PERFORMANCE_SAMPLES = @PERFORMANCE_SAMPLES + 1;
END WHILE COLLECT_PERFORMANCE_RUN;

select max(REDO_LOG_OCCUPANCY_PCT),
       max(THREADS_CONNECTED),
       max(RND_NEXT_PER_MIN),
       max(COM_SELECT_PER_MIN),
       max(COM_DML_PER_MIN),
       max(COM_XA_COMMIT_PER_MIN),
       max(SLOW_QUERIES_PER_MIN),
       max(LOCK_CURRENT_WAITS),
       min((1 - (IBP_READS_PER_MIN / IBP_READ_REQUESTS_PER_MIN)) * 100),
       max(MEMORY_USED),
       max(INNODB_BUFFER_POOL_DATA),
       max(BINLOG_COMMITS_PER_MIN),
       max(DATA_WRITES_PER_MIN),
       max(OS_LOG_WRITTEN_PER_MIN),
       max(COM_STMT_PREPARE_PER_MIN),
       max(COM_STMT_EXECUTE_PER_MIN),
       min(QCACHE_QUERIES_IN_CACHE),
       max(QCACHE_FREE_MEMORY),
       max(QCACHE_HITS_PER_MIN),
       max(QCACHE_INSERTS_PER_MIN),
       max(QCACHE_LOWMEM_PRUNES_PER_MIN),
	   max(INNODB_HISTORY_LIST_LENGTH)
INTO @TOP_REDO_OCPCY, @TOP_THREADS_CONNECTED, @TOP_RND_NEXT, @TOP_SELECT_MIN, @TOP_DML_MIN, @TOP_XA_COMMITS_MIN, @TOP_SLOW_QUERIES, @TOP_CURRENT_WAITS, @LOW_CACHE_HITS, @TOP_MEMORY_USED, @TOP_BUFFER_POOL_DATA, @BINLOG_COMMITS_MIN, @TOP_DATA_WRITES_MIN, @TOP_OS_LOG_WRITES, @TOP_STMT_PREPARE, @TOP_STMT_EXECUTE, @LOW_QUERIES_IN_CACHE, @TOP_QCACHE_FREE_MEM, @TOP_QCACHE_HITS, @TOP_QCACHE_INSERTS, @TOP_QCACHE_PRUNES, @TOP_HISTORY_LIST_LENGTH
from V_SERVER_PERFORMANCE_PER_MIN;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'PERFORMANCE RUN ID',@RUNID;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'PERFORMANCE SAMPLES COLLECTED',@PERFORMANCE_SAMPLES;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'THREADS CONNECTED / MAX CONNECTIONS',concat(@TOP_THREADS_CONNECTED,' / ',@@MAX_CONNECTIONS);

if @TOP_REDO_OCPCY is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX REDO OCCUPANCY PCT IN 1 MIN', @TOP_REDO_OCPCY;
end if;

if @TOP_RND_NEXT is not null and @TOP_RND_NEXT > 0  then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX ROWS SCANNED IN 1 MIN',@TOP_RND_NEXT;
end if;

if @TOP_SELECT_MIN is not null and @TOP_SELECT_MIN > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX SELECT STATEMENTS IN 1 MIN',@TOP_SELECT_MIN;
end if;

if @TOP_DML_MIN is not null and @TOP_DML_MIN > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX DML STATEMENTS IN 1 MIN',@TOP_DML_MIN;
end if;

if @BINLOG_COMMITS_MIN is not null and  @BINLOG_COMMITS_MIN > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX TXNS WRITTEN TO BINARY LOG 1 MIN',@BINLOG_COMMITS_MIN;
end if;

if @TOP_STMT_PREPARE is not null and  @TOP_STMT_PREPARE > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX PREPARED STMTS PREPARED 1 MIN',@TOP_STMT_PREPARE;
end if;

if @TOP_STMT_EXECUTE is not null and  @TOP_STMT_EXECUTE > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX PREPARED STMTS EXECUTED 1 MIN',@TOP_STMT_EXECUTE;
end if;

if @TOP_XA_COMMITS_MIN is not null and  @TOP_XA_COMMITS_MIN > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX XA COMMITS IN 1 MIN',@TOP_XA_COMMITS_MIN;
end if;

if @TOP_SLOW_QUERIES is not null and  @TOP_SLOW_QUERIES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX SLOW QUERIES IN 1 MIN',@TOP_SLOW_QUERIES;
end if;

if @TOP_CURRENT_WAITS is not null and @TOP_CURRENT_WAITS > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX LOCK WAITERS IN 1 MIN',@TOP_CURRENT_WAITS;
end if;

if @TOP_MEMORY_USED is not null and  @TOP_MEMORY_USED > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 
    if(@TOP_MEMORY_USED < @GB_THRESHOLD,
  'MEMORY USED FOR CONNECTIONS MB',
  'MEMORY USED FOR CONNECTIONS GB'
  ),
  if(@TOP_MEMORY_USED < @GB_THRESHOLD,
    concat(format(@TOP_MEMORY_USED/1024/1024,2),'M'),
    concat(format(@TOP_MEMORY_USED/1024/1024/1024,2),'G')
  );
end if;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) 
WITH RQ as (select 4 as `SECTION_ID`,'BUFFER CACHE HIT PCT SINCE STARTUP' as `ITEM`,
(select VARIABLE_VALUE from information_schema.GLOBAL_STATUS where VARIABLE_NAME='INNODB_BUFFER_POOL_READS' limit 1) as `READS`,
(select VARIABLE_VALUE from information_schema.GLOBAL_STATUS where VARIABLE_NAME='INNODB_BUFFER_POOL_READ_REQUESTS' limit 1) as `READ_REQUESTS`)
select `SECTION_ID`, `ITEM`, format(((1 - (`READS` / `READ_REQUESTS`)) * 100),6) as `PCT` from  RQ;

if @LOW_CACHE_HITS is not null THEN
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'LOWEST BUFFER CACHE HIT PCT 1 MIN',if(@LOW_CACHE_HITS=100,format(@LOW_CACHE_HITS,5), format(@LOW_CACHE_HITS,6));
end if;

/* INNODB PERFORMANCE SECTION START */

if @TOP_DATA_WRITES_MIN is not null and  @TOP_DATA_WRITES_MIN > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX INNODB DATA WRITE OPS 1 MIN',@TOP_DATA_WRITES_MIN;
end if;

if @TOP_HISTORY_LIST_LENGTH is not null and @TOP_HISTORY_LIST_LENGTH > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX INNODB HISTORY LIST LENGTH',@TOP_HISTORY_LIST_LENGTH;
end if;

-- ignore less than 12,000 bytes
if @TOP_OS_LOG_WRITES is not null and  @TOP_OS_LOG_WRITES > 12000 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, if(@TOP_OS_LOG_WRITES < @GB_THRESHOLD,
    'MAX INNODB LOG WRITES 1 MIN MB',
    'MAX INNODB LOG WRITES 1 MIN GB'),
  if(@TOP_OS_LOG_WRITES < @GB_THRESHOLD,
    concat(format(@TOP_OS_LOG_WRITES/1024/1024,2),'M'),
    concat(format(@TOP_OS_LOG_WRITES/1024/1024/1024,2),'G')
    );
end if;

if @TOP_BUFFER_POOL_DATA is not null and @TOP_BUFFER_POOL_DATA > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 
  if(@TOP_BUFFER_POOL_DATA < @GB_THRESHOLD,
    'INNODB BUFFER POOL DATA MB',
    'INNODB BUFFER POOL DATA GB'
    ),
  if(@TOP_BUFFER_POOL_DATA < @GB_THRESHOLD,
    concat(format(@TOP_BUFFER_POOL_DATA/1024/1024,2),'M'), 
    concat(format(@TOP_BUFFER_POOL_DATA/1024/1024/1024,2),'G')
  );
end if;

SELECT VARIABLE_VALUE INTO @REDO_LOG_WAITS
  FROM information_schema.GLOBAL_STATUS
  WHERE variable_name='INNODB_LOG_WAITS';

if  @REDO_LOG_WAITS > 0 then
SELECT VARIABLE_VALUE INTO @REDO_LOG_WAITS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_LOG_WAITS';
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)  
  select 4,'INNODB REDO LOG WAITS SINCE STARTUP',@REDO_LOG_WAITS;
end if;

select VARIABLE_VALUE into @ALL_ROW_LOCK_WAITS
from information_schema.GLOBAL_STATUS
WHERE variable_name='INNODB_ROW_LOCK_WAITS';

if @ALL_ROW_LOCK_WAITS > 0 then
select VARIABLE_VALUE into @ALL_ROW_LOCK_WAITS 
from information_schema.GLOBAL_STATUS 
WHERE variable_name='INNODB_ROW_LOCK_WAITS';
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) 
  select 4, 'INNODB ROW LOCK WAITS SINCE STARTUP', @ALL_ROW_LOCK_WAITS;
end if;

/* INNODB PERFORMANCE SECTION END */



/* QUERY CACHE SECTION START */
if @QUERY_CACHE_ENABLED != 'OFF' AND @QUERY_CACHE_SIZE > 0 then
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, concat('QUERY CACHE IS ',@QUERY_CACHE_ENABLED,', USING MEMORY ',if(@QUERY_CACHE_SIZE < @GB_THRESHOLD,'MB','GB')),
  if(@QUERY_CACHE_SIZE < @GB_THRESHOLD,
    concat(format(@QUERY_CACHE_SIZE/1024/1024,2),'M'), 
    concat(format(@QUERY_CACHE_SIZE/1024/1024/1024,2),'G')
    );
end if;

if @QUERY_CACHE_ENABLED != 'OFF' AND @QUERY_CACHE_SIZE > 0 then

if @LOW_QUERIES_IN_CACHE is not null and  @LOW_QUERIES_IN_CACHE > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'LOW QUERIES IN QUERY CACHE',@LOW_QUERIES_IN_CACHE;
end if;

if @TOP_QCACHE_FREE_MEM is not null and  @TOP_QCACHE_FREE_MEM > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, concat('HIGHEST QUERY CACHE FREE MEMORY ',if(@TOP_QCACHE_FREE_MEM < @GB_THRESHOLD,'MB','GB')),
    if(@TOP_QCACHE_FREE_MEM < @GB_THRESHOLD,
    concat(format(@TOP_QCACHE_FREE_MEM/1024/1024,2),'M'), 
    concat(format(@TOP_QCACHE_FREE_MEM/1024/1024/1024,2),'G')
    );
end if;

if @TOP_QCACHE_HITS is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX QUERY CACHE HITS 1 MIN',@TOP_QCACHE_HITS;
end if;

if @TOP_QCACHE_INSERTS is not null and @TOP_QCACHE_INSERTS > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX QUERIES INSERTED INTO QCACHE 1 MIN',@TOP_QCACHE_INSERTS;
end if;

if @TOP_QCACHE_PRUNES is not null and @TOP_QCACHE_PRUNES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX QUERIES REMOVED FROM QCACHE 1 MIN',@TOP_QCACHE_PRUNES;
end if;

end if; 
/* QUERY CACHE SECTION END */

/* GALERA TO SERVER_STATE SECTION START */
if @IS_GALERA='YES' then
select
max(WSREP_FLOW_CONTROL_PAUSED_NS_PER_MIN),max(WSREP_FLOW_CONTROL_RECV_PER_MIN),max(WSREP_FLOW_CONTROL_SENT_PER_MIN),
max(WSREP_LAST_COMMITTED_PER_MIN),max(WSREP_LOCAL_COMMITS_PER_MIN),max(WSREP_RECEIVED_PER_MIN),
max(WSREP_RECEIVED_BYTES_PER_MIN),max(WSREP_REPLICATED_PER_MIN),max(WSREP_REPLICATED_BYTES_PER_MIN),
max(WSREP_REPL_DATA_BYTES_PER_MIN),max(WSREP_REPL_KEYS_PER_MIN),max(WSREP_REPL_KEYS_BYTES_PER_MIN)
INTO
@TOP_FLOW_CONTROL_PAUSED_NS,@TOP_FLOW_CONTROL_RECV,@TOP_FLOW_CONTROL_SENT,
@TOP_LAST_COMMITTED,@TOP_LOCAL_COMMITS,@TOP_RECEIVED,
@TOP_RECEIVED_BYTES,@TOP_REPLICATED,@TOP_REPLICATED_BYTES,
@TOP_REPL_DATA_BYTES,@TOP_REPL_KEYS,@TOP_REPL_KEYS_BYTES
from V_GALERA_PERFORMANCE_PER_MIN;

if @TOP_FLOW_CONTROL_PAUSED_NS is not null and @TOP_FLOW_CONTROL_PAUSED_NS > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'FLOW CNTRL: MAX NANOSCNDS IN PAUSED STATE 1 MIN',@TOP_FLOW_CONTROL_PAUSED_NS;
end if;

if @TOP_FLOW_CONTROL_RECV is not null and @TOP_FLOW_CONTROL_RECV > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'FLOW CNTRL: MAX PAUSE EVENTS RECVD 1 MIN',@TOP_FLOW_CONTROL_RECV;
end if;

if @TOP_FLOW_CONTROL_SENT is not null and @TOP_FLOW_CONTROL_SENT > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'FLOW CONTROL: MAX PAUSE EVENTS SENT 1 MIN',@TOP_FLOW_CONTROL_SENT;
end if;

if @TOP_LAST_COMMITTED is not null and @TOP_LAST_COMMITTED > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX WSREP COMMITS 1 MIN',@TOP_LAST_COMMITTED;
end if;

if @TOP_LOCAL_COMMITS is not null and @TOP_LOCAL_COMMITS > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX WSREP LOCAL COMMITS 1 MIN',@TOP_LOCAL_COMMITS;
end if;

if @TOP_RECEIVED is not null and @TOP_RECEIVED > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX WSREP WRITESETS RECEIVED 1 MIN',@TOP_RECEIVED;
end if;

if @TOP_RECEIVED_BYTES is not null and @TOP_RECEIVED_BYTES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX BYTES OF WRITESETS RECEIVED 1 MIN',@TOP_RECEIVED_BYTES;
end if;

if @TOP_REPLICATED is not null and @TOP_REPLICATED > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX WRITESETS REPLICATED TO OTHER NODES 1 MIN',@TOP_REPLICATED;
end if;

if @TOP_REPLICATED_BYTES is not null and @TOP_REPLICATED_BYTES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX BYTES OF WRITESETS TO OTHER NODES 1 MIN',@TOP_REPLICATED_BYTES;
end if;

if @TOP_REPL_DATA_BYTES is not null and @TOP_REPL_DATA_BYTES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX TOTAL SIZE OF DATA REPLICATED 1 MIN',@TOP_REPL_DATA_BYTES;
end if;

if @TOP_REPL_KEYS is not null and @TOP_REPL_KEYS > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX TOTAL OF KEYS REPLICATED 1 MIN',@TOP_REPL_KEYS;
end if;

if @TOP_REPL_KEYS_BYTES is not null and @TOP_REPL_KEYS_BYTES > 0 then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 7, 'MAX BYTES OF KEYS REPLICATED 1 MIN',@TOP_REPL_KEYS_BYTES;
end if;
end if;
/* GALERA TO SERVER_STATE SECTION END */
else -- if @TIMES_TO_COLLECT_PERF_STATS > 0
  SIGNAL SQLSTATE '01000' 
  SET MESSAGE_TEXT="Performace and Warnings collection are disabled.", 
  MYSQL_ERRNO = 1000;
  show warnings;
end if; -- if @TIMES_TO_COLLECT_PERF_STATS > 0

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)  
  select 6 as `SECTION_ID`, substr(ITEM,1,72) as `ITEM`, substr(STATUS,1,72) as `STATUS` 
  from REVIEW_WARNINGS 
  where `RUN_ID` = @RUNID;
  
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) 
VALUES (1, 'REVIEW COMPLETES',now());

UPDATE `CURRENT_RUN` set `RUN_END` = now(), `STATUS`= 'COMPLETED' where ID=1;

end if; -- if @DO_NOTHING = 'YES'
end;
//

delimiter ;

select * from V_SERVER_STATE order by ID asc;
