locals {
  dashboard_name = "${var.service_name}-${var.environment}-rds"
  region         = data.aws_region.current.name
  db_identifier  = aws_db_instance.this.identifier
  db_resource_id = aws_db_instance.this.resource_id

  pi = "DB_PERF_INSIGHTS('RDS', '${local.db_resource_id}'"
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({
    widgets = flatten([

      # ── Header row: stat widgets ──────────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 6
          height = 3
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Questions.avg')", label = "QPS", id = "e1" }]
            ]
            view   = "singleValue"
            region = local.region
            title  = "Current QPS"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 6
          y      = 0
          width  = 6
          height = 3
          properties = {
            metrics = [
              [{ expression = "m1 / 1024 / 1024 / 1024", label = "GiB", id = "e1" }],
              ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", local.db_identifier,
              { id = "m1", visible = false }]
            ]
            view   = "singleValue"
            region = local.region
            title  = "Free Storage (GiB)"
            period = 300
            stat   = "Average"
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 6
          height = 3
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Users.Threads_running.avg')", label = "Threads Running", id = "e1" }]
            ]
            view   = "singleValue"
            region = local.region
            title  = "Threads Running"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 18
          y      = 0
          width  = 6
          height = 3
          properties = {
            metrics = [
              ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.db_identifier]
            ]
            view   = "singleValue"
            region = local.region
            title  = "Connections"
            period = 300
            stat   = "Average"
          }
        },
      ],

      # ── Row 1: Connections ────────────────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 3
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Users.Threads_connected.avg')", label = "Threads_connected", id = "e1" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Connections"
            period = 60
            annotations = {
              horizontal = [
                { value = local.connections_threshold, label = "Alarm threshold" },
                { value = local.default_max_connections, label = "max_connections" },
              ]
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 3
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Users.Aborted_connects.avg')", label = "Aborted_connects", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Users.Aborted_clients.avg')", label = "Aborted_clients", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Aborted Connections"
            period = 60
          }
        },
      ],

      # ── Row 2: Client Threads ─────────────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 9
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Users.Threads_running.avg')", label = "Threads_running", id = "e1" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Client Threads — Running"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 9
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Users.Threads_created.avg')", label = "Threads_created", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Users.Threads_connected.avg')", label = "Threads_connected", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Client Threads — Connected / Created"
            period = 60
          }
        },
      ],

      # ── Row 3: Temporary Objects & Slow Queries ───────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 15
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Temp.Created_tmp_tables.avg')", label = "Created_tmp_tables", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Temp.Created_tmp_disk_tables.avg')", label = "Created_tmp_disk_tables", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Temporary Objects"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 15
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Slow_queries.avg')", label = "Slow_queries", id = "e1" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Slow Queries (> ${var.long_query_time}s)"
            period = 60
          }
        },
      ],

      # ── Row 4: Select Types & Sorts ───────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 21
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Select_full_join.avg')", label = "Select_full_join", id = "e1" }],
              [{ expression = "${local.pi}, 'db.SQL.Select_scan.avg')", label = "Select_scan", id = "e2" }],
              [{ expression = "${local.pi}, 'db.SQL.Select_range.avg')", label = "Select_range", id = "e3" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Select Types"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 21
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Sort_rows.avg')", label = "Sort_rows", id = "e1" }],
              [{ expression = "${local.pi}, 'db.SQL.Sort_merge_passes.avg')", label = "Sort_merge_passes", id = "e2" }],
              [{ expression = "${local.pi}, 'db.SQL.Sort_scan.avg')", label = "Sort_scan", id = "e3" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Sorts"
            period = 60
          }
        },
      ],

      # ── Row 5: Table Locks & Questions ────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 27
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Locks.Table_locks_immediate.avg')", label = "Table_locks_immediate", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Locks.Table_locks_waited.avg')", label = "Table_locks_waited", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Table Locks"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 27
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Questions.avg')", label = "Questions", id = "e1" }],
              [{ expression = "${local.pi}, 'db.SQL.Com_select.avg')", label = "Com_select", id = "e2" }],
              [{ expression = "${local.pi}, 'db.SQL.Queries.avg')", label = "Queries", id = "e3" }],
            ]
            view    = "timeSeries"
            stacked = false
            region  = local.region
            title   = "MySQL Questions & Queries"
            period  = 60
          }
        },
      ],

      # ── Row 6: Network Traffic & IOPS ─────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 33
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "NetworkReceiveThroughput", "DBInstanceIdentifier", local.db_identifier],
              ["AWS/RDS", "NetworkTransmitThroughput", "DBInstanceIdentifier", local.db_identifier],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Network Traffic"
            period = 60
            stat   = "Average"
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 33
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", local.db_identifier],
              ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", local.db_identifier],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Read/Write IOPS"
            period = 60
            stat   = "Average"
          }
        },
      ],

      # ── Row 7: CPU & Memory (System) ──────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 39
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.db_identifier]
            ]
            view   = "timeSeries"
            region = local.region
            title  = "CPU Utilization"
            period = 60
            stat   = "Average"
            annotations = {
              horizontal = [
                { value = var.alarm_cpu_threshold, label = "Alarm threshold" }
              ]
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 39
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "m1 / 1024 / 1024", label = "Freeable Memory (MiB)", id = "e1" }],
              ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", local.db_identifier,
              { id = "m1", visible = false }]
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Freeable Memory (total: ${data.aws_ec2_instance_type.this.memory_size} MiB)"
            period = 60
            stat   = "Average"
            yAxis = {
              left = { label = "MiB" }
            }
            annotations = {
              horizontal = [
                {
                  value = floor(local.memory_threshold_bytes / 1024 / 1024),
                  label = "Alarm (${var.alarm_memory_percent}% = ${floor(local.memory_threshold_bytes / 1024 / 1024)} MiB)"
                }
              ]
            }
          }
        },
      ],

      # ── Row 8: Disk Queue & Free Storage ──────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 45
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "DiskQueueDepth", "DBInstanceIdentifier", local.db_identifier]
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Disk Queue Depth"
            period = 60
            stat   = "Average"
            annotations = {
              horizontal = [
                { value = var.alarm_disk_queue_depth_threshold, label = "Alarm threshold" }
              ]
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 45
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "m1 / 1024 / 1024 / 1024", label = "Free Storage (GiB)", id = "e1" }],
              ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", local.db_identifier,
              { id = "m1", visible = false }]
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Free Storage Space (GiB)"
            period = 60
            stat   = "Average"
            yAxis = {
              left = { label = "GiB" }
            }
            annotations = {
              horizontal = [
                { value = var.allocated_storage, label = "Allocated (${var.allocated_storage} GiB)" },
                { value = var.max_allocated_storage, label = "Max (${var.max_allocated_storage} GiB)" },
                {
                  value = floor(local.storage_threshold_normal / 1024 / 1024 / 1024),
                  label = "Normal (${var.alarm_storage_percent_normal}% = ${floor(local.storage_threshold_normal / 1024 / 1024 / 1024)} GiB)"
                },
                {
                  value = floor(local.storage_threshold_high / 1024 / 1024 / 1024),
                  label = "High (${var.alarm_storage_percent_high}% = ${floor(local.storage_threshold_high / 1024 / 1024 / 1024)} GiB)"
                },
                {
                  value = floor(local.storage_threshold_urgent / 1024 / 1024 / 1024),
                  label = "Urgent (${var.alarm_storage_percent_urgent}% = ${floor(local.storage_threshold_urgent / 1024 / 1024 / 1024)} GiB)"
                },
              ]
            }
          }
        },
      ],

      # ── Row 9: InnoDB Row Operations & Transactions ─────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 51
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.SQL.Innodb_rows_read.avg')", label = "Innodb_rows_read", id = "e1" }],
              [{ expression = "${local.pi}, 'db.SQL.Innodb_rows_inserted.avg')", label = "Innodb_rows_inserted", id = "e2" }],
              [{ expression = "${local.pi}, 'db.SQL.Innodb_rows_updated.avg')", label = "Innodb_rows_updated", id = "e3" }],
              [{ expression = "${local.pi}, 'db.SQL.Innodb_rows_deleted.avg')", label = "Innodb_rows_deleted", id = "e4" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "InnoDB Row Operations"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 51
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Transactions.active_transactions.avg')", label = "Active transactions", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Transactions.trx_rseg_history_len.avg')", label = "History list length", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "InnoDB Transactions"
            period = 60
          }
        },
      ],

      # ── Row 10: Buffer Pool & Table Cache ─────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 57
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Cache.innoDB_buffer_pool_hit_rate.avg')", label = "Buffer pool hit rate", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Cache.innoDB_buffer_pool_usage.avg')", label = "Buffer pool usage", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "InnoDB Buffer Pool"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 57
          width  = 12
          height = 6
          properties = {
            metrics = [
              [{ expression = "${local.pi}, 'db.Cache.Opened_tables.avg')", label = "Opened_tables", id = "e1" }],
              [{ expression = "${local.pi}, 'db.Cache.Opened_table_definitions.avg')", label = "Opened_table_definitions", id = "e2" }],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "MySQL Table Cache"
            period = 60
          }
        },
      ],

      # ── Row 11: Read/Write Latency ────────────────────────────────────
      [
        {
          type   = "metric"
          x      = 0
          y      = 63
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", local.db_identifier],
              ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", local.db_identifier],
            ]
            view   = "timeSeries"
            region = local.region
            title  = "Read/Write Latency"
            period = 60
            stat   = "Average"
          }
        },
      ],
    ])
  })
}
