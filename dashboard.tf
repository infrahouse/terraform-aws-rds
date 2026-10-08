locals {
  dashboard_name = "${var.service_name}-${var.environment}-rds"
  region         = data.aws_region.current.name
  db_identifier  = aws_db_instance.this.identifier
  db_resource_id = aws_db_instance.this.resource_id

  pi = "DB_PERF_INSIGHTS('RDS', '${local.db_resource_id}'"

  memory_threshold_mib         = floor(local.memory_threshold_bytes / 1024 / 1024)
  storage_threshold_normal_gib = floor(local.storage_threshold_normal / 1024 / 1024 / 1024)
  storage_threshold_high_gib   = floor(local.storage_threshold_high / 1024 / 1024 / 1024)
  storage_threshold_urgent_gib = floor(local.storage_threshold_urgent / 1024 / 1024 / 1024)

  connections_annotations = {
    horizontal = [
      { value = local.connections_threshold, label = "Alarm threshold" },
      { value = local.default_max_connections, label = "max_connections" },
    ]
  }

  # Performance Insights widgets per engine. Each entry lists [counter, label] pairs (plus optional
  # per-metric options); any other attribute (annotations, stacked, view, period) is passed through
  # to the widget properties. Counter names come from "Performance Insights counter metrics" in the
  # RDS User Guide. "header" holds two single-value stats, "body" holds time series two per row.
  engine_pi_widgets = {
    mysql = {
      header = [
        { title = "Current QPS", metrics = [["db.SQL.Questions", "QPS"]] },
        { title = "Threads Running", metrics = [["db.Users.Threads_running", "Threads Running"]] },
      ]
      body = [
        # ── Connections ─────────────────────────────────────────────────
        {
          title       = "MySQL Connections"
          metrics     = [["db.Users.Threads_connected", "Threads_connected"]]
          annotations = local.connections_annotations
        },
        {
          title = "MySQL Aborted Connections"
          metrics = [
            ["db.Users.Aborted_connects", "Aborted_connects"],
            ["db.Users.Aborted_clients", "Aborted_clients"],
          ]
        },

        # ── Client Threads ──────────────────────────────────────────────
        {
          title   = "MySQL Client Threads — Running"
          metrics = [["db.Users.Threads_running", "Threads_running"]]
        },
        {
          title = "MySQL Client Threads — Connected / Created"
          metrics = [
            ["db.Users.Threads_created", "Threads_created"],
            ["db.Users.Threads_connected", "Threads_connected"],
          ]
        },

        # ── Temporary Objects & Slow Queries ────────────────────────────
        {
          title = "MySQL Temporary Objects"
          metrics = [
            ["db.Temp.Created_tmp_tables", "Created_tmp_tables"],
            ["db.Temp.Created_tmp_disk_tables", "Created_tmp_disk_tables"],
          ]
        },
        {
          title   = "MySQL Slow Queries (> ${var.long_query_time}s)"
          metrics = [["db.SQL.Slow_queries", "Slow_queries"]]
        },

        # ── Select Types & Sorts ────────────────────────────────────────
        {
          title = "MySQL Select Types"
          metrics = [
            ["db.SQL.Select_full_join", "Select_full_join"],
            ["db.SQL.Select_scan", "Select_scan"],
            ["db.SQL.Select_range", "Select_range"],
          ]
        },
        {
          title = "MySQL Sorts"
          metrics = [
            ["db.SQL.Sort_rows", "Sort_rows"],
            ["db.SQL.Sort_merge_passes", "Sort_merge_passes"],
            ["db.SQL.Sort_scan", "Sort_scan"],
          ]
        },

        # ── Table Locks & Questions ─────────────────────────────────────
        {
          title = "MySQL Table Locks"
          metrics = [
            ["db.Locks.Table_locks_immediate", "Table_locks_immediate"],
            ["db.Locks.Table_locks_waited", "Table_locks_waited"],
          ]
        },
        {
          title = "MySQL Questions & Queries"
          metrics = [
            ["db.SQL.Questions", "Questions"],
            ["db.SQL.Com_select", "Com_select"],
            ["db.SQL.Queries", "Queries"],
          ]
          stacked = false
        },

        # ── InnoDB Row Operations & Transactions ────────────────────────
        {
          title = "InnoDB Row Operations"
          metrics = [
            ["db.SQL.Innodb_rows_read", "Innodb_rows_read"],
            ["db.SQL.Innodb_rows_inserted", "Innodb_rows_inserted"],
            ["db.SQL.Innodb_rows_updated", "Innodb_rows_updated"],
            ["db.SQL.Innodb_rows_deleted", "Innodb_rows_deleted"],
          ]
        },
        {
          title = "InnoDB Transactions"
          metrics = [
            ["db.Transactions.active_transactions", "Active transactions"],
            ["db.Transactions.trx_rseg_history_len", "History list length"],
          ]
        },

        # ── Buffer Pool & Table Cache ───────────────────────────────────
        {
          title = "InnoDB Buffer Pool"
          metrics = [
            ["db.Cache.innoDB_buffer_pool_hit_rate", "Buffer pool hit rate"],
            ["db.Cache.innoDB_buffer_pool_usage", "Buffer pool usage"],
          ]
        },
        {
          title = "MySQL Table Cache"
          metrics = [
            ["db.Cache.Opened_tables", "Opened_tables"],
            ["db.Cache.Opened_table_definitions", "Opened_table_definitions"],
          ]
        },
      ]
    }

    postgres = {
      header = [
        { title = "Commits per Second", metrics = [["db.Transactions.xact_commit", "Commits/s"]] },
        { title = "Active Transactions", metrics = [["db.Transactions.active_transactions", "Active"]] },
      ]
      body = [
        # ── Connections ─────────────────────────────────────────────────
        {
          title       = "PostgreSQL Connections"
          metrics     = [["db.User.numbackends", "numbackends"]]
          annotations = local.connections_annotations
        },
        {
          title   = "PostgreSQL Connection Attempts (per minute)"
          metrics = [["db.User.total_auth_attempts", "total_auth_attempts"]]
        },

        # ── Transactions ────────────────────────────────────────────────
        {
          title = "PostgreSQL Commits & Rollbacks (per second)"
          metrics = [
            ["db.Transactions.xact_commit", "xact_commit"],
            ["db.Transactions.xact_rollback", "xact_rollback"],
          ]
        },
        {
          title = "PostgreSQL Transaction States"
          metrics = [
            ["db.Transactions.active_transactions", "Active"],
            ["db.Transactions.blocked_transactions", "Blocked"],
            ["db.state.idle_in_transaction_count", "Idle in transaction"],
          ]
        },

        # ── Tuples & Deadlocks ──────────────────────────────────────────
        {
          title = "PostgreSQL Tuple Operations (per second)"
          metrics = [
            ["db.SQL.tup_returned", "tup_returned"],
            ["db.SQL.tup_fetched", "tup_fetched"],
            ["db.SQL.tup_inserted", "tup_inserted"],
            ["db.SQL.tup_updated", "tup_updated"],
            ["db.SQL.tup_deleted", "tup_deleted"],
          ]
        },
        {
          title   = "PostgreSQL Deadlocks (per minute)"
          metrics = [["db.Concurrency.deadlocks", "deadlocks"]]
        },

        # ── Buffer Cache & Read Latency ─────────────────────────────────
        {
          title = "PostgreSQL Buffer Cache Hits vs Reads (blocks per second)"
          metrics = [
            ["db.Cache.blks_hit", "blks_hit (cache)"],
            ["db.IO.blks_read", "blks_read (disk)"],
          ]
        },
        {
          title   = "PostgreSQL Block Read Latency (ms)"
          metrics = [["db.IO.read_latency", "read_latency"]]
        },

        # ── Checkpoints ─────────────────────────────────────────────────
        {
          title = "PostgreSQL Checkpoints (per minute)"
          metrics = [
            ["db.Checkpoint.checkpoints_timed", "checkpoints_timed"],
            ["db.Checkpoint.checkpoints_req", "checkpoints_req"],
          ]
        },
        {
          title = "PostgreSQL Checkpoint Latency (ms per checkpoint)"
          metrics = [
            ["db.Checkpoint.checkpoint_write_latency", "write"],
            ["db.Checkpoint.checkpoint_sync_latency", "sync"],
          ]
        },

        # ── Temporary Files & Transaction ID Age ────────────────────────
        {
          title = "PostgreSQL Temporary Files"
          metrics = [
            ["db.Temp.temp_files", "temp_files (per minute)"],
            ["db.Temp.temp_bytes", "temp_bytes (per second)", { yAxis = "right" }],
          ]
        },
        {
          title = "PostgreSQL Transaction ID Age (wraparound risk)"
          metrics = [
            ["db.Transactions.max_used_xact_ids", "Unvacuumed transactions"],
            ["db.Transactions.oldest_running_transaction_xid_age", "Oldest running transaction age"],
          ]
        },
      ]
    }
  }

  # Expand the compact entries above into CloudWatch widgets backed by DB_PERF_INSIGHTS() expressions
  pi_header_defaults = { view = "singleValue", region = local.region, period = 300 }
  pi_body_defaults   = { view = "timeSeries", region = local.region, period = 60 }
  engine_widgets = {
    for section, defaults in { header = local.pi_header_defaults, body = local.pi_body_defaults } :
    section => [
      for w in local.engine_pi_widgets[var.engine][section] : {
        type = "metric"
        properties = merge(
          defaults,
          {
            title = w.title
            metrics = [
              for i, m in w.metrics :
              [merge({ expression = "${local.pi}, '${m[0]}.avg')", label = m[1], id = "e${i + 1}" }, try(m[2], {}))]
            ]
          },
          { for k, v in w : k => v if !contains(["title", "metrics"], k) },
        )
      }
    ]
  }

  # ── Engine-neutral widgets (AWS/RDS namespace) ─────────────────────────
  free_storage_stat = {
    type = "metric"
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
  }

  connections_stat = {
    type = "metric"
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
  }

  system_widgets = [
    # ── Network Traffic & IOPS ──────────────────────────────────────────
    {
      type = "metric"
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
      type = "metric"
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

    # ── CPU & Memory ────────────────────────────────────────────────────
    {
      type = "metric"
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
      type = "metric"
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
              value = local.memory_threshold_mib,
              label = "Alarm (${var.alarm_memory_percent}% = ${local.memory_threshold_mib} MiB)"
            }
          ]
        }
      }
    },

    # ── Disk Queue & Free Storage ───────────────────────────────────────
    {
      type = "metric"
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
      type = "metric"
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
              value = local.storage_threshold_normal_gib,
              label = "Normal (${var.alarm_storage_percent_normal}% = ${local.storage_threshold_normal_gib} GiB)"
            },
            {
              value = local.storage_threshold_high_gib,
              label = "High (${var.alarm_storage_percent_high}% = ${local.storage_threshold_high_gib} GiB)"
            },
            {
              value = local.storage_threshold_urgent_gib,
              label = "Urgent (${var.alarm_storage_percent_urgent}% = ${local.storage_threshold_urgent_gib} GiB)"
            },
          ]
        }
      }
    },

    # ── Read/Write Latency ──────────────────────────────────────────────
    {
      type = "metric"
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
  ]

  # Engine stats on the left of each pair, shared stats on the right
  header_widgets = [
    local.engine_widgets.header[0],
    local.free_storage_stat,
    local.engine_widgets.header[1],
    local.connections_stat,
  ]
  body_widgets = concat(local.engine_widgets.body, local.system_widgets)
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({
    widgets = concat(
      # One row of 6x3 stats, then 12x6 time series, two per row
      [for i, w in local.header_widgets : merge(w, { x = i * 6, y = 0, width = 6, height = 3 })],
      [
        for i, w in local.body_widgets :
        merge(w, { x = (i % 2) * 12, y = 3 + floor(i / 2) * 6, width = 12, height = 6 })
      ],
    )
  })
}
