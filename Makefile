.PHONY: bridge widget test install uninstall

bridge:
	cd bridge && swift build -c release

widget:
	cd widget && ./build.sh

# build.sh always emits AgentTouchBar.pock plus matching .pkarchive files.
package: widget
	@echo "Archives are built by widget/build.sh; see widget/dist/."

test: bridge widget
	cd bridge && (./.build/release/AgentBridge > /tmp/ab-test.log 2>&1 & echo $$! > /tmp/ab-test.pid)
	sleep 0.5
	@curl -sf localhost:3939/v1/health > /dev/null && echo "bridge health: OK" || echo "bridge health: FAIL"
	@curl -sf -X POST localhost:3939/v1/event -d '{"agent":"claude","event":"tool_start","tool":"Edit","detail":"x"}' > /dev/null && echo "event: OK" || echo "event: FAIL"
	@curl -sf localhost:3939/v1/state | grep -q "working" && echo "state: OK" || echo "state: FAIL"
	@kill $$(cat /tmp/ab-test.pid) 2>/dev/null || true
	@cd widget && swiftc -o dist/smoke-test tests/smoke.swift && ./dist/smoke-test
	@cd widget && swiftc -parse-as-library -o dist/render-test tests/render.swift Sources/*.swift -I dist -L dist/lib -lPockKit -Xlinker -rpath -Xlinker "$$PWD/dist/lib" && ./dist/render-test | grep -v "^{\"ok"

install:
	./install.sh

uninstall:
	./uninstall.sh
