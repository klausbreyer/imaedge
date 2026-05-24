ENV_FILE := /Users/kb0/versioned/imaedge/.env

.PHONY: prepare test start

prepare:
	mix deps.get
	mix assets.setup
	mix compile

test: prepare
	mix test

start: prepare
	@test -f "$(ENV_FILE)" || { echo "Env file not found: $(ENV_FILE)" >&2; exit 1; }
	@set -a && . "$(ENV_FILE)" && set +a && mix ecto.migrate && mix phx.server --open
