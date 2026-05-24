defmodule Imaedge.Repo.RuntimeConfig do
  @moduledoc false

  def build(env_getter \\ &System.get_env/1) do
    database_url =
      env_getter.("DATABASE_URL") ||
        raise """
        environment variable DATABASE_URL is missing.
        For example: ecto://USER:PASS@HOST/DATABASE
        """

    maybe_ipv6 = if env_getter.("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
    queue_target = String.to_integer(env_getter.("DB_QUEUE_TARGET") || "5000")
    queue_interval = String.to_integer(env_getter.("DB_QUEUE_INTERVAL") || "10000")

    [
      url: database_url,
      pool_size: String.to_integer(env_getter.("POOL_SIZE") || "5"),
      socket_options: maybe_ipv6,
      queue_target: queue_target,
      queue_interval: queue_interval
    ] ++ ssl_options_from_url(database_url)
  end

  defp ssl_options_from_url(database_url) do
    parsed_url = URI.parse(database_url)

    parsed_url.query
    |> case do
      nil ->
        []

      query ->
        query_params = URI.decode_query(query)

        case Map.get(query_params, "sslmode") do
          "verify-full" ->
            root_cert = Map.get(query_params, "sslrootcert") || System.get_env("PGSSLROOTCERT") || "sqlca.pem"

            [
              ssl: [
                verify: :verify_peer,
                cacertfile: Path.expand(root_cert, File.cwd!()),
                server_name_indication: String.to_charlist(parsed_url.host),
                customize_hostname_check: [
                  match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
                ]
              ]
            ]

          "require" ->
            [ssl: [verify: :verify_none]]

          _other -> []
        end
    end
  end
end
