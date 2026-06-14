import logging
import logging.handlers
import os
import random
import time
from contextlib import contextmanager
from datetime import datetime, timezone

import psycopg2
from psycopg2 import pool as pg_pool
from flask import Flask, jsonify

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Logging setup — format follows Datadog's recommended Python log correlation:
# https://docs.datadoghq.com/tracing/other_telemetry/connect_logs_and_traces/python/
# ---------------------------------------------------------------------------
LOG_DIR = os.getenv("LOG_DIR", "/var/log/app")
os.makedirs(LOG_DIR, exist_ok=True)

FORMAT = (
    "%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] "
    "[dd.service=%(dd.service)s dd.env=%(dd.env)s dd.version=%(dd.version)s "
    "dd.trace_id=%(dd.trace_id)s dd.span_id=%(dd.span_id)s] "
    "- %(message)s"
)


class DDContextFilter(logging.Filter):
    """Provides dd.* defaults when SSI has not yet injected trace context."""
    _DD_ATTRS = {
        "dd.trace_id": "0",
        "dd.span_id": "0",
        "dd.service": "",
        "dd.env": "",
        "dd.version": "",
    }

    def filter(self, record):
        for attr, default in self._DD_ATTRS.items():
            if not hasattr(record, attr):
                setattr(record, attr, default)
        return True


file_handler = logging.handlers.TimedRotatingFileHandler(
    os.path.join(LOG_DIR, "python-app.log"), when="midnight", backupCount=7
)
file_handler.setFormatter(logging.Formatter(FORMAT))
file_handler.addFilter(DDContextFilter())

console_handler = logging.StreamHandler()
console_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))

logging.basicConfig(level=logging.INFO, handlers=[file_handler, console_handler])
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Database (lazy initialization — does not affect existing endpoints)
# ---------------------------------------------------------------------------
_pg_pool = None


def get_pool():
    global _pg_pool
    if _pg_pool is None:
        _pg_pool = pg_pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=5,
            host=os.environ["DB_HOST"],
            port=int(os.environ.get("DB_PORT", "5432")),
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            connect_timeout=5,
        )
    return _pg_pool


@contextmanager
def conn_cursor():
    conn = get_pool().getconn()
    try:
        with conn.cursor() as cur:
            yield conn, cur
        conn.commit()
    finally:
        get_pool().putconn(conn)


def _months():
    """Return (current_month, prev_month) as 'YYYY-MM' strings."""
    now = datetime.now(timezone.utc)
    curr = now.strftime("%Y-%m")
    prev = f"{now.year - 1}-12" if now.month == 1 else f"{now.year}-{now.month - 1:02d}"
    return curr, prev


def init_db():
    """Create schema and seed sample data if empty. Idempotent."""
    schema = """
    CREATE TABLE IF NOT EXISTS users (
        id         SERIAL PRIMARY KEY,
        name       VARCHAR(100) NOT NULL,
        email      VARCHAR(100) NOT NULL,
        created_at TIMESTAMP    NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS orders (
        id         SERIAL PRIMARY KEY,
        user_id    INTEGER      NOT NULL REFERENCES users(id),
        product    VARCHAR(100) NOT NULL,
        amount     INTEGER      NOT NULL,
        created_at TIMESTAMP    NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
    """
    with conn_cursor() as (_, cur):
        cur.execute(schema)
        cur.execute("SELECT count(*) FROM users")
        if cur.fetchone()[0] > 0:
            logger.info("init_db: users table already seeded, skipping")
            return

        logger.info("init_db: seeding users and orders")
        products = ["widget", "gadget", "gizmo", "doohickey", "thingamajig"]
        for i in range(1, 51):
            cur.execute(
                "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id",
                (f"User{i:03d}", f"user{i:03d}@example.com"),
            )
            uid = cur.fetchone()[0]
            for _ in range(random.randint(5, 20)):
                cur.execute(
                    "INSERT INTO orders (user_id, product, amount) VALUES (%s, %s, %s)",
                    (uid, random.choice(products), random.randint(100, 5000)),
                )
        logger.info("init_db: seed complete")


def init_analytics_db():
    """Create order_monthly_stats table and seed data. Idempotent."""
    schema = """
    CREATE TABLE IF NOT EXISTS order_monthly_stats (
        id           SERIAL PRIMARY KEY,
        user_id      INTEGER    NOT NULL REFERENCES users(id),
        year_month   VARCHAR(7) NOT NULL,
        total_amount INTEGER    NOT NULL,
        order_count  INTEGER    NOT NULL,
        created_at   TIMESTAMP  NOT NULL DEFAULT now(),
        UNIQUE(user_id, year_month)
    );
    """
    with conn_cursor() as (_, cur):
        cur.execute(schema)
        cur.execute("SELECT count(*) FROM order_monthly_stats")
        if cur.fetchone()[0] > 0:
            logger.info("init_analytics_db: already seeded, skipping")
            return

        curr, prev = _months()
        logger.info("init_analytics_db: seeding curr=%s prev=%s", curr, prev)
        for user_id in range(1, 51):
            cur.execute(
                "INSERT INTO order_monthly_stats (user_id, year_month, total_amount, order_count) "
                "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                (user_id, curr, random.randint(1000, 9999), random.randint(5, 20)),
            )
            if user_id % 7 != 0:
                cur.execute(
                    "INSERT INTO order_monthly_stats (user_id, year_month, total_amount, order_count) "
                    "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                    (user_id, prev, random.randint(1000, 9999), random.randint(5, 20)),
                )
        logger.info("init_analytics_db: seed complete")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.route("/api/data")
def get_data():
    logger.info("GET /api/data called")
    return jsonify({
        "message": "Hello from Python",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@app.route("/api/timeout")
def get_timeout():
    # Simulate a slow response 30% of the time (3 out of 10 requests)
    if random.random() < 0.3:
        logger.info("GET /api/timeout - simulating 10-second delay (30%% probability triggered)")
        time.sleep(10)

    logger.info("GET /api/timeout - responding")
    return jsonify({
        "message": "Hello from Python (timeout endpoint)",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@app.route("/api/error")
def get_error():
    if random.random() < 0.2:
        logger.error("GET /api/error - simulating error response (20%% probability triggered)")
        return jsonify({
            "error": "internal_error",
            "message": "An unexpected error occurred in Python service",
        }), 500

    logger.info("GET /api/error - responding normally")
    return jsonify({
        "message": "Hello from Python (error endpoint)",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@app.route("/api/db/normal")
def db_normal():
    logger.info("GET /api/db/normal - single JOIN query")
    with conn_cursor() as (_, cur):
        cur.execute(
            """
            SELECT u.id, u.name, o.id, o.product, o.amount
            FROM users u
            LEFT JOIN orders o ON o.user_id = u.id
            ORDER BY u.id, o.id
            LIMIT 200
            """
        )
        rows = cur.fetchall()
    return jsonify({
        "message": "single JOIN query (1 DB span expected)",
        "row_count": len(rows),
    })


@app.route("/api/db/n1")
def db_n1():
    logger.info("GET /api/db/n1 - N+1 query pattern")
    with conn_cursor() as (_, cur):
        cur.execute("SELECT id, name FROM users ORDER BY id LIMIT 20")
        users = cur.fetchall()
        result = []
        for uid, name in users:
            cur.execute(
                "SELECT id, product, amount FROM orders WHERE user_id = %s",
                (uid,),
            )
            result.append({"user_id": uid, "name": name, "order_count": len(cur.fetchall())})
    return jsonify({
        "message": "N+1 query pattern (21 DB spans expected: 1 + 20)",
        "user_count": len(result),
    })


@app.route("/api/db/long-run")
def db_long_run():
    logger.info("GET /api/db/long-run - 35s sleep query")
    with conn_cursor() as (_, cur):
        cur.execute("SELECT pg_sleep(35), count(*) FROM users")
        row = cur.fetchone()
    return jsonify({
        "message": "long-running query (35s DB span expected)",
        "sleep_seconds": 35,
        "user_count": row[1],
    })


@app.route("/api/analytics")
def analytics():
    curr, prev = _months()
    user_id = random.randint(1, 50)
    with conn_cursor() as (_, cur):
        cur.execute(
            "SELECT total_amount, order_count FROM order_monthly_stats "
            "WHERE user_id = %s AND year_month = %s",
            (user_id, curr),
        )
        curr_row = cur.fetchone()
        cur.execute(
            "SELECT COALESCE(SUM(total_amount), 0) FROM order_monthly_stats "
            "WHERE user_id = %s AND year_month = %s",
            (user_id, prev),
        )
        prev_amount = cur.fetchone()[0]

    current_amount = curr_row[0] if curr_row else 0
    order_count = curr_row[1] if curr_row else 0
    logger.info("analytics: user_id=%d current_month=%d prev_month=%d orders=%d",
                user_id, current_amount, prev_amount, order_count)
    growth_rate = (current_amount - prev_amount) / prev_amount * 100
    return jsonify({
        "user_id": user_id,
        "current_month": curr,
        "current_amount": current_amount,
        "prev_amount": prev_amount,
        "growth_rate": round(growth_rate, 2),
        "order_count": order_count,
    })


@app.route("/api/analytics/summary")
def analytics_summary():
    curr, prev = _months()
    cohort = random.randint(0, 6)
    user_ids = [uid for uid in range(1, 51) if uid % 7 == cohort]
    logger.info("analytics_summary: cohort=%d user_ids=%s curr=%s prev=%s",
                cohort, user_ids, curr, prev)
    results = []
    for uid in user_ids:
        with conn_cursor() as (_, cur):
            cur.execute(
                "SELECT COALESCE(SUM(total_amount), 0) FROM order_monthly_stats "
                "WHERE user_id = %s AND year_month = %s",
                (uid, curr),
            )
            current = cur.fetchone()[0]
            cur.execute(
                "SELECT COALESCE(SUM(total_amount), 0) FROM order_monthly_stats "
                "WHERE user_id = %s AND year_month = %s",
                (uid, prev),
            )
            prev_val = cur.fetchone()[0]
        logger.info("analytics_summary: user_id=%d current=%d prev=%d", uid, current, prev_val)
        growth_rate = (current - prev_val) / prev_val * 100
        results.append({"user_id": uid, "growth_rate": round(growth_rate, 2)})
    return jsonify({
        "cohort": cohort,
        "user_count": len(results),
        "results": results,
    })


if __name__ == "__main__":
    try:
        init_db()
    except Exception as e:
        logger.exception("init_db failed (continuing without DB): %s", e)
    try:
        init_analytics_db()
    except Exception as e:
        logger.exception("init_analytics_db failed (continuing without analytics): %s", e)
    port = int(os.getenv("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
