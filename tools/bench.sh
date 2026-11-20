#!/usr/bin/env bash
# tools/bench.sh :: run dkbench scenarios against a temporary install (`make bench`).
#
# Environment (all optional):
#   BIN=build/release/dk  DKBENCH=build/release/dkbench
#   BENCH_SCENARIO=mixed      comma list of pages, fights, static, mixed, idle, realtime,
#                             realtime-mixed, soak, or "all" (pages to idle)
#   BENCH_CLIENTS=50  BENCH_RATE=10 (req/s per client; 0 = closed loop)  BENCH_THREADS=4
#   BENCH_SECONDS (or BENCH_DURATION): measured seconds (default 10; realtime-mixed 20,
#                             soak 3600)  BENCH_WARMUP=3  BENCH_IDLE=1000 (connections for "idle")
#   BENCH_LISTENERS=1000 (event streams for "realtime"; idle players for realtime-mixed and
#                             soak)  BENCH_EVENTS=10 (events/s published by "realtime")
#   realtime-mixed and soak: BENCH_CHAT=2 (chat messages/s)  BENCH_CHURN=1 (stream
#                             reconnects/s)  BENCH_SAMPLE=30 (soak: seconds between samples)
#                             BENCH_RSS_SLOPE=1024 (soak: KiB/h)  BENCH_CSV=file (soak samples;
#                             default ${TMPDIR:-/tmp}/dk-soak-<date>.csv)
#   BENCH_SERVER_CPUS=10,11   taskset CPU list for the server ("" = no pinning)
#   BENCH_CLIENT_CPUS=4-7     taskset CPU list for dkbench
#   BENCH_WORKERS=            config `workers` (unset: the config default)
#   BENCH_CONFIG='k = v, ...' extra config.lua keys
#   BENCH_KEEP=1              keep the temp dir (server log, database)
#   BENCH_PORT=N              listen on port N (default: any free port)
#   BENCH_LOG=file            server log (default: in the temp dir; needs BENCH_PORT if
#                             it is not a regular file, e.g. /dev/null)
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${BIN:-build/release/dk}
DKBENCH=${DKBENCH:-build/release/dkbench}
case $BIN in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
case $DKBENCH in /*) ;; *) DKBENCH="$ROOT/$DKBENCH" ;; esac
SCENARIOS=${BENCH_SCENARIO:-mixed}
[ "$SCENARIOS" = all ] && SCENARIOS=pages,fights,static,mixed,idle
CLIENTS=${BENCH_CLIENTS:-50}
RATE=${BENCH_RATE:-10}
THREADS=${BENCH_THREADS:-4}
DURATION=${BENCH_SECONDS:-${BENCH_DURATION:-}}
WARMUP=${BENCH_WARMUP:-3}
IDLE=${BENCH_IDLE:-1000}
LISTENERS=${BENCH_LISTENERS:-1000}
EVENTS=${BENCH_EVENTS:-10}
CHAT=${BENCH_CHAT:-2}
CHURN=${BENCH_CHURN:-1}
SERVER_CPUS=${BENCH_SERVER_CPUS-10,11}
CLIENT_CPUS=${BENCH_CLIENT_CPUS-4-7}

[ -x "$BIN" ] || { echo "bench: $BIN not found" >&2; exit 1; }
[ -x "$DKBENCH" ] || { echo "bench: $DKBENCH not found" >&2; exit 1; }

PIN_SERVER=()
PIN_CLIENT=()
if command -v taskset >/dev/null; then
	[ -n "$SERVER_CPUS" ] && PIN_SERVER=(taskset -c "$SERVER_CPUS")
	[ -n "$CLIENT_CPUS" ] && PIN_CLIENT=(taskset -c "$CLIENT_CPUS")
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/dk-bench.XXXXXX")
SERVER_PID=
cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
	if [ "${BENCH_KEEP:-0}" = 1 ]; then echo "bench: kept $T"; else rm -rf "$T"; fi
}
trap cleanup EXIT

cp -r "$ROOT/app" "$ROOT/templates" "$ROOT/public" "$T/"
{
	echo "return {"
	echo "	port = ${BENCH_PORT:-0}, db_path = \"$T/dk.db\", app_dir = \"$T/app\", template_dir = \"$T/templates\","
	echo "	public_dir = \"$T/public\", outbox_dir = \"$T/outbox\", secret = \"bench\", dev = false,"
	echo "	pbkdf2_iterations = 1000, keepalive_timeout = 120, max_connections = 4096,"
	echo "	max_streams = 4096, max_streams_per_ip = 0, test_routes = true,"
	# realtime-mixed, soak: presence leaves within seconds, so stream churn makes them
	case ",$SCENARIOS," in *,realtime-mixed,*|*,soak,*) echo "	online_seconds = 10, presence_sweep_seconds = 5," ;; esac
	[ -n "${BENCH_WORKERS:-}" ] && echo "	workers = $BENCH_WORKERS,"
	[ -n "${BENCH_CONFIG:-}" ] && echo "	$BENCH_CONFIG,"
	echo "}"
} > "$T/config.lua"
"$BIN" install --config "$T/config.lua" --admin admin admin@example.com benchadmin \
	>"$T/install.log" 2>&1 || { cat "$T/install.log" >&2; exit 1; }
(cd "$T/public" && find . -type f | sort | sed 's#^\./#/static/#') > "$T/static.txt"

ulimit -n "$(ulimit -Hn)" 2>/dev/null || true    # realtime: a descriptor per stream
t0=$(date +%s.%N)
"${PIN_SERVER[@]}" "$BIN" serve --config "$T/config.lua" >"${BENCH_LOG:-$T/server.log}" 2>&1 &
SERVER_PID=$!
PORT=
for _ in $(seq 1 3000); do   # sanitizer builds start slowly
	if [ -n "${BENCH_PORT:-}" ]; then
		curl -s -o /dev/null "http://127.0.0.1:$BENCH_PORT/login" && PORT=$BENCH_PORT
	else
		PORT=$(sed -n 's/.*http: listening on [^ ]*:\([0-9][0-9]*\)$/\1/p' "$T/server.log" | head -n1)
	fi
	[ -n "$PORT" ] && break
	kill -0 "$SERVER_PID" 2>/dev/null || break
	sleep 0.01
done
[ -n "$PORT" ] || { echo "bench: server did not start" >&2; cat "$T/server.log" >&2; exit 1; }
until curl -s -o /dev/null "http://127.0.0.1:$PORT/login"; do sleep 0.005; done
t1=$(date +%s.%N)

echo "== dk bench: $("$BIN" version)"
echo "machine: $(nproc) CPUs ($(uname -m)), $(uname -sr); server on CPUs ${SERVER_CPUS:-any}, dkbench on CPUs ${CLIENT_CPUS:-any}"
echo "cold start to first response: $(awk "BEGIN { printf \"%.0f\", ($t1 - $t0) * 1000 }") ms"
grep -m1 'dk listening' "$T/server.log" | sed 's/^.*\] /server: /'

STATUS=0
IFS=, read -r -a LIST <<< "$SCENARIOS"
for s in "${LIST[@]}"; do
	echo
	case $s in
	idle)
		echo "-- idle: $IDLE keep-alive connections"
		"${PIN_CLIENT[@]}" "$DKBENCH" -p "$PORT" -s idle -c "$IDLE" -d 5 -x "$SERVER_PID" -S "$T/static.txt"
		;;
	realtime)
		echo "-- realtime: $LISTENERS event streams, $EVENTS events/s"
		"${PIN_CLIENT[@]}" "$DKBENCH" -p "$PORT" -s realtime -l "$LISTENERS" -e "$EVENTS" -t "$THREADS" \
			-d "${DURATION:-10}" -x "$SERVER_PID" -u live
		;;
	pages|fights|static|mixed)
		echo "-- $s"
		"${PIN_CLIENT[@]}" "$DKBENCH" -p "$PORT" -s "$s" -c "$CLIENTS" -t "$THREADS" -r "$RATE" \
			-d "${DURATION:-10}" -w "$WARMUP" -x "$SERVER_PID" -S "$T/static.txt"
		;;
	realtime-mixed|soak)
		secs=${DURATION:-20}
		extra=()
		if [ "$s" = soak ]; then
			secs=${DURATION:-3600}
			extra=(-i "${BENCH_SAMPLE:-30}" -g "${BENCH_RSS_SLOPE:-1024}"
				-o "${BENCH_CSV:-${TMPDIR:-/tmp}/dk-soak-$(date +%Y%m%d-%H%M%S).csv}")
		fi
		echo "-- $s: $LISTENERS idle players and $CLIENTS active ones with event streams, $CHAT chat messages/s, $CHURN reconnects/s, $secs s"
		"${PIN_CLIENT[@]}" "$DKBENCH" -p "$PORT" -s "$s" -l "$LISTENERS" -c "$CLIENTS" -t "$THREADS" -r "$RATE" \
			-e "$CHAT" -j "$CHURN" -d "$secs" -w "$WARMUP" -x "$SERVER_PID" -S "$T/static.txt" \
			-k "$T/dk.sock" -D "$T/dk.db" "${extra[@]}" || STATUS=1
		;;
	*) echo "bench: unknown scenario $s" >&2; exit 2 ;;
	esac
done

if "$BIN" help 2>&1 | grep -q '^  stats'; then
	echo
	echo "-- dk stats"
	"$BIN" stats --config "$T/config.lua"
fi

t2=$(date +%s.%N)
kill "$SERVER_PID" && wait "$SERVER_PID" 2>/dev/null
t3=$(date +%s.%N)
SERVER_PID=
echo
echo "shutdown: $(awk "BEGIN { printf \"%.0f\", ($t3 - $t2) * 1000 }") ms"
if grep -q '\[error\]' "$T/server.log"; then
	echo "bench: errors in the server log:" >&2
	grep -A3 '\[error\]' "$T/server.log" | head -20 >&2
fi
# sanitizer builds (make bench BENCH_BUILD=dbg|tsan) report to the server's stderr
if grep -qE 'ERROR: (Address|Leak)Sanitizer|runtime error:|WARNING: ThreadSanitizer' "$T/server.log"; then
	echo "bench: sanitizer reports in the server log:" >&2
	grep -E -A20 'ERROR: (Address|Leak)Sanitizer|runtime error:|WARNING: ThreadSanitizer' "$T/server.log" | head -80 >&2
	STATUS=1
elif nm "$BIN" 2>/dev/null | grep -qE '__(a|t)san_init'; then
	echo "sanitizers: no reports in the server log"
fi
exit $STATUS
