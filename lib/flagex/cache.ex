if Code.ensure_loaded?(Nebulex) do
  defmodule Flagex.Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :flagex,
      adapter: Nebulex.Adapters.Replicated,
      primary_storage_adapter: Nebulex.Adapters.Cachex
  end
end
