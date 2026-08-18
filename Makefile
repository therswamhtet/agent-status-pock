.PHONY: bridge widget test install uninstall

bridge:
	cd bridge && swift build -c release

widget:
	cd widget && ./build.sh

# build.sh always emits AgentTouchBar.pock plus matching .pkarchive files.
package: widget
	@echo "Archives are built by widget/build.sh; see widget/dist/."

test: bridge widget
	@set -e; (cd bridge && AGENTBRIDGE_PORT=39390 exec ./.build/release/AgentBridge > /tmp/ab-test.log 2>&1) & \
	pid=$$!; trap 'kill $$pid 2>/dev/null || true' EXIT; set -e; \
	for attempt in $$(seq 1 20); do curl -fsS localhost:39390/v1/health > /dev/null && break; test $$attempt -lt 20 || { cat /tmp/ab-test.log >&2; exit 1; }; sleep 0.25; done; \
	echo "bridge health: OK"; \
	curl -fsS -X POST localhost:39390/v1/event -d '{"agent":"claude","event":"tool_start","tool":"Edit","detail":"x"}' > /dev/null; echo "event: OK"; \
	curl -fsS localhost:39390/v1/state | grep -q "working"; echo "state: OK"
	@cd widget && swiftc -o dist/smoke-test tests/smoke.swift && ./dist/smoke-test
	@cd widget && swiftc -parse-as-library -o dist/render-test tests/render.swift Sources/*.swift -I dist -L dist/lib -lPockKit -Xlinker -rpath -Xlinker "$$PWD/dist/lib" && ./dist/render-test | grep -v "^{\"ok"

install:
	./install.sh

uninstall:
	./uninstall.sh
