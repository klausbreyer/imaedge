ENV_FILE := /Users/kb0/versioned/imaedge/.env

.PHONY: prepare test kill-port-4000 start brand brand-clean

prepare:
	mix deps.get
	mix assets.setup
	mix compile

test: prepare
	mix test

kill-port-4000:
	@pids="$$(lsof -tiTCP:4000 -sTCP:LISTEN 2>/dev/null)"; \
	if [ -n "$$pids" ]; then \
		echo "Stopping processes on port 4000: $$pids"; \
		kill $$pids 2>/dev/null || true; \
		sleep 1; \
		pids="$$(lsof -tiTCP:4000 -sTCP:LISTEN 2>/dev/null)"; \
		if [ -n "$$pids" ]; then \
			echo "Force stopping processes on port 4000: $$pids"; \
			kill -9 $$pids 2>/dev/null || true; \
		fi; \
	fi

brand:
	@$(MAKE) -C priv/brand build

brand-clean:
	@$(MAKE) -C priv/brand clean

start:
	@$(MAKE) kill-port-4000
	@$(MAKE) prepare
	@$(MAKE) brand
	@test -f "$(ENV_FILE)" || { echo "Env file not found: $(ENV_FILE)" >&2; exit 1; }
	@device="$$(networksetup -listallhardwareports 2>/dev/null | awk '/^Hardware Port: Ethernet$$/ { getline; sub(/^Device: /, ""); print; exit }')"; \
	if [ -z "$$device" ]; then echo "Ethernet hardware port not found" >&2; exit 1; fi; \
	host="$$(ipconfig getifaddr "$$device" 2>/dev/null)"; \
	if [ -z "$$host" ]; then echo "No IPv4 address found for Ethernet device $$device" >&2; exit 1; fi; \
	url="http://$$host:4000"; \
	echo "Opening $$url"; \
	set -a && . "$(ENV_FILE)" && set +a && export PHX_HOST="$$host" && mix ecto.migrate && open "$$url" && mix phx.server
