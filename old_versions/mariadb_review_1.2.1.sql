/* MariaDB Review */
/* Script by Edward Stoever for MariaDB Support */

/* SESSION SQL_LOG_BIN=OFF ENSURES THIS WILL NOT REPLICATE OR EFFECT GTIDs. In almost all cases it should be OFF. */
SET SESSION SQL_LOG_BIN=OFF;

/* TIMES_TO_COLLECT_PERF_STATS is how many times performance stats and warnings will be collected. */
/* Each time adds 1 minute to the run of this script. */
/* Minimum recommended is 10. Must be at least 2 to compare with previous collection. */
/* Disable collection of performance stats setting it to 0.*/
/* You can set @TIMES_TO_COLLECT_PERF_STATS to a very large number to run indefinitely. */
/* Stop the script gracefully from a new session by updating the ID column on ITERATION table: */
/* update ITERATION set ID=0 where 1=1; -- STOPS COLLECTING PERFORMANCE STATS AND ENDS SCRIPT PROPERLY */
set @TIMES_TO_COLLECT_PERF_STATS=4;

/* DROP_OLD_SCHEMA_CREATE_NEW = NO in order to conserve data from previous runs of this script. */
/* Conserve runs to compare separate runs. */
set @DROP_OLD_SCHEMA_CREATE_NEW='YES';


/* -------- DO NOT MAKE CHANGES BELOW THIS LINE --------- */
set @MARIADB_REVIEW_VERSION='1.2.1';
set @REDO_WARNING_THRESHOLD=50;
set @LONG_RUNNING_TRX_THRESHOLD_MINUTES = 30; 

delimiter //
begin not atomic

if @DROP_OLD_SCHEMA_CREATE_NEW = 'YES' THEN
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

if @SERVER_STATE_EXISTS='YES' THEN
  select concat('RENAME TABLE mariadb_review.SERVER_STATE TO mariadb_review.SERVER_STATE_OLD_',date_format(str_to_date(`STATUS`,'%Y-%m-%d %H:%i:%S'),'%Y_%m_%d_%H_%i_%S')) into @SQL 
  from mariadb_review.SERVER_STATE where ITEM='REVIEW STARTS';
  if @SQL is not null then
  	PREPARE STMT FROM @SQL;
	EXECUTE STMT;
	DEALLOCATE PREPARE STMT;
  end if;
end if;

end;
//
delimiter ;

create schema if not exists mariadb_review;
use mariadb_review;
drop table if exists `SERVER_STATE`;

CREATE TABLE `SERVER_STATE` (
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
  `LOCK_CURRENT_WAITS` int(11) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

CREATE TABLE IF NOT EXISTS `REVIEW_WARNINGS` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `FIRST_SEEN` timestamp NOT NULL DEFAULT current_timestamp(),
  `LAST_SEEN` timestamp NOT NULL DEFAULT current_timestamp(),
  `HOSTNAME` varchar(128) DEFAULT NULL,
  `RUN_ID` varchar(12) DEFAULT NULL,
  `ITEM` varchar(100) DEFAULT NULL,
  `STATUS` varchar(100) DEFAULT NULL,
  `INFO` longtext DEFAULT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UK_RUN_ID_ITEM` (`RUN_ID`,`ITEM`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

DROP TABLE IF EXISTS `SECTION_TITLES`;
CREATE TABLE `SECTION_TITLES` (
  `SECTION_ID` int(11) NOT NULL,
  `TITLE` varchar(72) NOT NULL,
  PRIMARY KEY (`SECTION_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
INSERT INTO `SECTION_TITLES` VALUES (1,'SERVER'),(2,'TOPOLOGY'),(3,'SCHEMAS'),(4,'PERFORMANCE'),(5,'GLOBALS'),(6,'WARNINGS');

DROP TABLE IF EXISTS `ITERATION`;
CREATE TABLE `ITERATION` (
  `ID` int(11) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
INSERT INTO `ITERATION` (`ID`) VALUES (@TIMES_TO_COLLECT_PERF_STATS);
select ID into @REMAINING from ITERATION where 1=1 limit 1;

drop view if exists V_SERVER_PERFORMANCE_PER_MIN;

CREATE VIEW V_SERVER_PERFORMANCE_PER_MIN as
select ID, RUN_ID, TICK, HOSTNAME, REDO_LOG_OCCUPANCY_PCT, THREADS_CONNECTED, LOCK_CURRENT_WAITS,
HANDLER_READ_RND_NEXT - (LAG(HANDLER_READ_RND_NEXT,1) OVER (ORDER BY ID)) as RND_NEXT_PER_MIN,
COM_SELECT - (LAG(COM_SELECT,1) OVER (ORDER BY ID)) as COM_SELECT_PER_MIN,
COM_DML - (LAG(COM_DML,1) OVER (ORDER BY ID)) as COM_DML_PER_MIN
from SERVER_PERFORMANCE
where RUN_ID = (select RUN_ID from SERVER_PERFORMANCE where ID = (select max(ID) from SERVER_PERFORMANCE));

drop view if exists V_SERVER_STATE;

create view V_SERVER_STATE as
select A.ID as ID, B.TITLE as SECTION, A.ITEM as ITEM, 
  if(A.STATUS REGEXP '^-?[0-9]+$' = 1,format(A.STATUS,0),A.STATUS) as STATUS
from SERVER_STATE A inner join SECTION_TITLES B 
ON A.SECTION_ID=B.SECTION_ID;

delimiter //
begin not atomic

set @POINT_VERSION=substring_index(substring_index(version(),'.',2),'.',-1);
if NOT @POINT_VERSION REGEXP '^[0-9]+$' then 
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'POINT_VERSION is not numeric.';
end if;

if @POINT_VERSION < 5 then
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
select if(VARIABLE_VALUE='Primary','YES','NO') into @IS_GALERA 
  from information_schema.global_status 
  where VARIABLE_NAME='WSREP_CLUSTER_STATUS';

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
select 1, 'ESTIMATED DATA FILES MB',concat(round(sum(DATA_LENGTH + INDEX_LENGTH)/ 1024 / 1024),'M')  from information_schema.TABLES;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 1, 'INNODB REDO LOG CAPACITY MB', concat(round(@LOG_FILE_CAPACITY /1024/1024),'M');
if @BINARY_LOGGING != 'ON' then
 insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
 select 1, 'BINARY LOGGING','OFF';
end if;


/* SECTION 2 REPLICATION AND TOPOLOGY */
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
if @BINARY_LOGGING = 'ON' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME = 'LOG_SLAVE_UPDATES';
end if;
  if @CONFIGURED_SLAVE_WORKERS > 0 THEN
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'CONFIGURED SLAVE WORKERS',@CONFIGURED_SLAVE_WORKERS;
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
    select 2, 'RUNNING SLAVE WORKERS',@RUNNING_SLAVE_WORKERS;
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
	select 2, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME='SLAVE_PARALLEL_MODE';
  ELSE
    insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
    (2,'PARALLEL REPLICATION','OFF');
  end if;
end if;

if @BINARY_LOGGING = 'ON' then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, VARIABLE_NAME, VARIABLE_VALUE from information_schema.global_variables where VARIABLE_NAME='BINLOG_FORMAT';
end if;

if @IS_GALERA ='YES' THEN
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'IS MEMBER OF GALERA CLUSTER', @IS_GALERA;
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 2, 'GALERA CLUSTER SIZE', @GALERA_CLUSTER_SIZE;
end if;


/* SECTION 3 USER SCHEMAS AND TABLES */
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED SCHEMAS', count(*) from information_schema.schemata where SCHEMA_NAME not in
('information_schema','performance_schema','sys','mysql') having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED TABLES', count(*) from information_schema.tables where TABLE_SCHEMA not in
('information_schema','performance_schema','sys','mysql') and TABLE_TYPE <> 'VIEW' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED VIEWS', count(*) from information_schema.tables where TABLE_SCHEMA not in
('information_schema','performance_schema','sys','mysql') and TABLE_TYPE = 'VIEW' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED ROUTINES', count(*) from information_schema.routines where ROUTINE_SCHEMA not in
('information_schema','performance_schema','sys','mysql') having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED PARTITIONED TABLES', count(distinct TABLE_SCHEMA,TABLE_NAME) as partitioned_table_count 
FROM information_schema.partitions 
WHERE PARTITION_NAME is not null
AND TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql') 
group by TABLE_SCHEMA,TABLE_NAME having count(*) > 0;


insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED INDEXES', count(*) 
from information_schema.`STATISTICS`
where INDEX_SCHEMA not in ('information_schema','performance_schema','sys','mysql');
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED TRIGGERS', count(*) 
from information_schema.`TRIGGERS`
where TRIGGER_SCHEMA not in ('information_schema','performance_schema','sys','mysql');
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES MyISAM ENGINE', count(*) from information_schema.tables where engine='MyISAM' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES INNODB ROW_FORMAT REDUNDANT', count(*) 
from information_schema.tables where engine='InnoDB' and row_format='Redundant' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES INNODB ROW_FORMAT COMPACT', count(*) 
from information_schema.tables where engine='InnoDB' and row_format='Compact' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'TABLES INNODB ROW_FORMAT COMPRESSED', count(*) 
from information_schema.tables where engine='InnoDB' and row_format='Compressed' having count(*) > 0;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'COLUMNSTORE ENGINE TABLES', count(*)  from information_schema.tables where engine='Columnstore' having count(*) > 0;
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 3, 'USER CREATED MEMORY ENGINE TABLES', COUNT(*) 
from information_schema.tables where engine='MEMORY' and TABLE_SCHEMA not in ('information_schema','performance_schema','sys','mysql') having count(*) > 0;
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
select 3, 'TABLES WITHOUT PRIMARY KEY',count(*) 
FROM information_schema.TABLES AS t LEFT JOIN information_schema.KEY_COLUMN_USAGE AS c 
ON t.TABLE_SCHEMA = c.CONSTRAINT_SCHEMA    
AND t.TABLE_NAME = c.TABLE_NAME    
AND c.CONSTRAINT_NAME = 'PRIMARY' 
WHERE t.TABLE_SCHEMA != 'information_schema'    
AND t.TABLE_SCHEMA NOT IN ('performance_schema','mysql','sys')    
AND t.TABLE_TYPE not in ( 'VIEW','SYSTEM VIEW')    
AND t.ENGINE != 'Columnstore'    
AND c.CONSTRAINT_NAME IS NULL;

/* SECTION 4 PERFORMANCE */
if @TIMES_TO_COLLECT_PERF_STATS > 0 then

if @TIMES_TO_COLLECT_PERF_STATS = 1 then
  SIGNAL SQLSTATE '01000' 
  SET MESSAGE_TEXT="Set TIMES_TO_COLLECT_PERF_STATS to 2 or more in order to generate comparison values.", 
  MYSQL_ERRNO = 1000;
  show warnings;
end if;

select substr(md5(rand()),floor(rand()*6)+1,10) into @RUNID;

select concat('Collecting Performance Data. This will take about ',format(@TIMES_TO_COLLECT_PERF_STATS,0),' minutes.') as NOTE;
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

SELECT VARIABLE_VALUE INTO @ROW_LOCK_CURRENT_WAITS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_ROW_LOCK_CURRENT_WAITS';
	 
INSERT INTO `SERVER_PERFORMANCE` 
(RUN_ID,TICK,HOSTNAME,REDO_LOG_OCCUPANCY_PCT,THREADS_CONNECTED,HANDLER_READ_RND_NEXT,COM_SELECT,COM_DML,LOCK_CURRENT_WAITS)
SELECT @RUNID, now(), @@hostname, @OCCUPANCY, @THREADS, @RND_NEXT, @COM_SEL, @COM_DML, @ROW_LOCK_CURRENT_WAITS;

select concat('Performance statistics run number ',format((@TIMES_TO_COLLECT_PERF_STATS - @REMAINING)+1,0),' of ',format(@TIMES_TO_COLLECT_PERF_STATS,0),' completed.') as NOTE;

/* POPULATE WARINGS TABLE START */

if @REPLICA_RUNNING = 'YES' then
  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 'MULTI-ROW UPDATE FROM MASTER, NO INDEX',
  concat(`DB`,'.',SUBSTRING_INDEX(SUBSTRING_INDEX(`STATE`,'`',2),'`',-1)),`INFO`
  from information_schema.processlist
  where `USER` = 'system user' 
  and `COMMAND` in ('Slave_SQL','Slave_worker')
  and `STATE` like 'Update_rows_log_event::find_row(-1) on table%' limit 1
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();

  insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
  select @RUNID,@@hostname, 'MULTI-ROW DELETE FROM MASTER, NO INDEX',
  concat(`DB`,'.',SUBSTRING_INDEX(SUBSTRING_INDEX(`STATE`,'`',2),'`',-1)),`INFO`
  from information_schema.processlist
  where `USER` = 'system user' 
  and `COMMAND` in ('Slave_SQL','Slave_worker')
  and `STATE` like 'Delete_rows_log_event::find_row(-1) on table%' limit 1
  ON DUPLICATE KEY UPDATE LAST_SEEN=now();
end if; -- @REPLICA_RUNNING = 'YES'

if @OCCUPANCY >= @REDO_WARNING_THRESHOLD THEN
    insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO) VALUES 
    (@RUNID,@@hostname, 'REDO OCCUPANCY IS HIGH',concat(@OCCUPANCY,'%'), NULL)
	ON DUPLICATE KEY UPDATE LAST_SEEN=now();
end if;

insert into `REVIEW_WARNINGS` (RUN_ID,HOSTNAME,ITEM,STATUS,INFO)
select @RUNID,@@hostname,concat('LONG RUNNING TRX (PID ',B.ID,')') as ITEM,
if(B.USER='system user',concat(B.USER,', trx started ',date_format(A.trx_started,'%b %d %H:%i')),concat(B.USER,'@',B.HOST,', trx started ',date_format(A.trx_started,'%b %d %H:%i'))) as STATUS,
-- concat(B.USER,'@',B.HOST,', trx started ',date_format(A.trx_started,'%b %d %H:%i')) as STATUS,
NULL as INFO
from information_schema.INNODB_TRX A
INNER JOIN information_schema.PROCESSLIST B on (A.trx_mysql_thread_id = B.ID)
WHERE A.trx_started < now() - interval @LONG_RUNNING_TRX_THRESHOLD_MINUTES minute
ON DUPLICATE KEY UPDATE LAST_SEEN=now();

/* POPULATE WARINGS TABLE END */

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
       max(LOCK_CURRENT_WAITS)
INTO @TOP_REDO_OCPCY, @TOP_THREADS_CONNECTED, @TOP_RND_NEXT, @TOP_SELECT_MIN, @TOP_DML_MIN, @TOP_CURRENT_WAITS
from V_SERVER_PERFORMANCE_PER_MIN;


insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'PERFORMANCE RUN ID',@RUNID;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'PERFORMANCE SAMPLES COLLECTED',@PERFORMANCE_SAMPLES;

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'THREADS CONNECTED / MAX CONNECTIONS',concat(@TOP_THREADS_CONNECTED,' / ',@@MAX_CONNECTIONS);

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
select 4, 'MAX REDO OCCUPANCY PCT IN 1 MIN', @TOP_REDO_OCPCY;

if @TOP_RND_NEXT is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX ROWS SCANNED IN 1 MIN',@TOP_RND_NEXT where @TOP_RND_NEXT > 0;
end if;

if @TOP_SELECT_MIN is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX SELECT STATEMENTS IN 1 MIN',@TOP_SELECT_MIN where @TOP_SELECT_MIN > 0;
end if;

if @TOP_DML_MIN is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX DML STATEMENTS IN 1 MIN',@TOP_DML_MIN where @TOP_DML_MIN > 0;
end if;

if @TOP_CURRENT_WAITS is not null then
  insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)
  select 4, 'MAX LOCK WAITERS IN 1 MIN',@TOP_CURRENT_WAITS where @TOP_CURRENT_WAITS > 0;
end if;

select VARIABLE_VALUE into @ALL_ROW_LOCK_WAITS 
from information_schema.GLOBAL_STATUS 
WHERE variable_name='INNODB_ROW_LOCK_WAITS';
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) 
  select 4, 'ROW LOCK WAITS SINCE STARTUP', @ALL_ROW_LOCK_WAITS where @ALL_ROW_LOCK_WAITS  > 0;

SELECT VARIABLE_VALUE INTO @REDO_LOG_WAITS
  FROM information_schema.GLOBAL_STATUS 
  WHERE variable_name='INNODB_LOG_WAITS';
insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)  
  select 4,'INNODB REDO LOG WAITS SINCE STARTUP',@REDO_LOG_WAITS where @REDO_LOG_WAITS > 0;  

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`)  
  select 6, ITEM, STATUS from REVIEW_WARNINGS 
  where RUN_ID = @RUNID;

else -- if @TIMES_TO_COLLECT_PERF_STATS > 0
  SIGNAL SQLSTATE '01000' 
  SET MESSAGE_TEXT="Performace and Warnings collection are disabled.", 
  MYSQL_ERRNO = 1000;
  show warnings;
end if; -- if @TIMES_TO_COLLECT_PERF_STATS > 0

insert into `SERVER_STATE` (`SECTION_ID`,`ITEM`,`STATUS`) VALUES
(1, 'REVIEW COMPLETES',now());

end;
//

delimiter ;

select * from V_SERVER_STATE;

