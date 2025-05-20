# In config/config.exs
import Config

config :blockchain_benchmark,
  # Default timeout for generic_node receive loop
  node_receive_timeout: 30_000, # milliseconds
  # DPoS specific settings
  dpos_delegates: 5,
  dpos_block_time_ms: 3,
  # Benchee settings (can be overridden by CLI args in the Mix task)
  benchee_warmup: 0, # seconds (0 for quick dev runs, 2-5 for real benchmarks)
  benchee_time: 1    # seconds (1 for quick dev runs, 5-10 for real benchmarks)

# Example: For test environment, you might want faster Benchee runs
# import_config "#{config_env()}.exs"
