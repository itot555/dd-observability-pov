import json
import logging
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
# JSON logging for Datadog log-trace correlation.
# JSON format lets Datadog parse dd.trace_id / dd.span_id as first-class
# attributes without relying on grok parsers (plain-text formats can miss them).
# DD_LOGS_INJECTION=true causes ddtrace to set these attributes on each
# LogRecord via a makeRecord patch before the formatter runs.
# ---------------------------------------------------------------------------

_DD_ATTRS = {
    "dd.trace_id": "0",
    "dd.span_id": "0",
    "dd.service": "",
    "dd.env": "",
    "dd.version": "",
}


class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S.%f%z"),
            "status": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for attr, default in _DD_ATTRS.items():
            entry[attr] = record.__dict__.get(attr, default)
        if record.exc_info:
            entry["error"] = {"stack": self.formatException(record.exc_info)}
        return json.dumps(entry, ensure_ascii=False)


handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())

logging.basicConfig(level=logging.INFO, handlers=[handler])
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


if __name__ == "__main__":
    try:
        init_db()
    except Exception as e:
        logger.exception("init_db failed (continuing without DB): %s", e)
    port = int(os.getenv("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
