New in Version 1.8.0:
- Working on Mariadb installed on Windows.
- New values in table GALERA_MARIADB_VERSIONS

New in Version 1.7.1:
- PROCESSLIST will now collect at least once depending on how @COLLECT_PROCESSLIST is set. The default value is NO which will collect 1 time.
- New table: GTID_POSITIONS
- Reporting READ_ONLY status when server is a REPLICA  

New in Version 1.7.0:
- Support for user without SUPER or BINLOG ADMIN privileges. create_user.sql is included to make it easy.
- Default is to REPLICATE. It can be set to NO but will require SUPER privilege to make it effective.
