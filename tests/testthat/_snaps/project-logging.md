# failed later audit insert rolls back the entire opening

    Code
      db_log_project(fixture$con, NULL, "Open")
    Condition
      Error:
      ! blocked

