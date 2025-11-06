#!/usr/bin/env python3
import argparse
import sys
import time

import psycopg2


if __name__ == "__main__":
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--db_host", required=True)
    arg_parser.add_argument("--db_port", required=True)
    arg_parser.add_argument("--db_user", required=True)
    arg_parser.add_argument("--db_password", required=True)
    arg_parser.add_argument(
        "--timeout",
        type=int,
        default=5,
        help="Maximum time to wait for the database (seconds).",
    )
    arg_parser.add_argument(
        "--initial-delay",
        type=float,
        default=0.5,
        help="Initial backoff delay in seconds.",
    )
    arg_parser.add_argument(
        "--max-delay", type=float, default=3.0, help="Maximum backoff delay in seconds."
    )

    args = arg_parser.parse_args()

    start_time = time.time()
    delay = max(args.initial_delay, 0.1)
    max_delay = max(args.max_delay, delay)
    error = ""
    attempt = 0
    while (time.time() - start_time) < args.timeout:
        attempt += 1
        try:
            conn = psycopg2.connect(
                user=args.db_user,
                host=args.db_host,
                port=args.db_port,
                password=args.db_password,
                dbname="postgres",
            )
        except psycopg2.OperationalError as e:
            error = e
            elapsed = time.time() - start_time
            remaining = max(args.timeout - elapsed, 0)
            print(
                f"Waiting for PostgreSQL (attempt {attempt}, "
                f"retrying in {delay:.1f}s, remaining {remaining:.1f}s)...",
                file=sys.stderr,
            )
        else:
            conn.close()
            error = ""
            break
        time.sleep(delay)
        delay = min(delay * 1.5, max_delay)

    if error:
        print("Database connection failure: %s" % error, file=sys.stderr)
        sys.exit(1)
    print("PostgreSQL is ready.", file=sys.stderr)
