# mariadb_review
SQL Script for Initial Review of MariaDB Server for Support tickets

This script can be run to assist support in solving problems with a MariaDB Server. It will create a schema called mariadb_review.

Sample Output:
```+----+-------------+-------------------------------------+----------------------------------+
| ID | SECTION     | ITEM                                | STATUS                           |
+----+-------------+-------------------------------------+----------------------------------+
|  1 | SERVER      | SCRIPT VERSION                      | 1.0.1                            |
|  2 | SERVER      | DATETIME OF REVIEW                  | 2023-05-18 13:45:46              |
|  3 | SERVER      | HOSTNAME                            | db01                             |
|  4 | SERVER      | DATABASE UPTIME                     | Since 18-May-2023 12:03:31       |
|  5 | SERVER      | CURRENT USER                        | root@localhost                   |
|  6 | SERVER      | SOFTWARE VERSION                    | 10.6.12-7-MariaDB-enterprise-log |
|  7 | SERVER      | DATADIR                             | /data/mariadb/                   |
|  8 | SERVER      | ESTIMATED DATA FILES MB             | 703M                             |
|  9 | SERVER      | INNODB REDO LOG CAPACITY MB         | 96M                              |
| 10 | TOPOLOGY    | IS A PRIMARY                        | NO                               |
| 11 | TOPOLOGY    | IS A REPLICA                        | NO                               |
| 12 | TOPOLOGY    | BINLOG_FORMAT                       | MIXED                            |
| 13 | SCHEMAS     | USER CREATED SCHEMAS                | 5                                |
| 14 | SCHEMAS     | USER CREATED TABLES                 | 22                               |
| 15 | SCHEMAS     | USER CREATED VIEWS                  | 12                               |
| 16 | SCHEMAS     | USER CREATED ROUTINES               | 64                               |
| 17 | SCHEMAS     | USER CREATED INDEXES                | 24                               |
| 18 | SCHEMAS     | USER CREATED TRIGGERS               | 0                                |
| 19 | SCHEMAS     | USER CREATED MEMORY ENGINE TABLES   | 1                                |
| 20 | SCHEMAS     | TABLES WITHOUT PRIMARY KEY          | 11                               |
| 21 | PERFORMANCE | PERFORMANCE RUN ID                  | 9b84d50392                       |
| 22 | PERFORMANCE | PERFORMANCE SAMPLES COLLECTED       | 10                               |
| 23 | PERFORMANCE | THREADS CONNECTED / MAX CONNECTIONS | 11 / 25                          |
| 24 | PERFORMANCE | MAX REDO OCCUPANCY PCT IN 1 MIN     | 10.53                            |
| 25 | PERFORMANCE | MAX ROWS SCANNED IN 1 MIN           | 44,823,591                       |
| 26 | PERFORMANCE | MAX SELECT STATEMENTS IN 1 MIN      | 393                              |
| 27 | PERFORMANCE | MAX DML STATEMENTS IN 1 MIN         | 30                               |
+----+-------------+-------------------------------------+----------------------------------+
```
