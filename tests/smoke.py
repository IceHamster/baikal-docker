#!/usr/bin/env python3
"""Exercise a built image using disposable containers; no host ports or data."""

from contextlib import contextmanager
import subprocess
import sys
import time
import uuid


IMAGE = sys.argv[1] if len(sys.argv) > 1 else "baikal:test"


def docker(*args, check=True, input=None, timeout=30):
    return subprocess.run(
        ["docker", *args],
        input=input,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
        timeout=timeout,
    )


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def eventually(predicate, message, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.2)
    raise AssertionError(message)


def health(name):
    return docker("inspect", "--format", "{{.State.Health.Status}}", name).stdout.strip()


@contextmanager
def container():
    name = "baikal-smoke-" + uuid.uuid4().hex[:12]
    try:
        docker(
            "run", "-d", "--name", name, "--network", "none",
            "--health-interval=1s", "--health-timeout=5s",
            "--health-start-period=0s", "--health-retries=2", IMAGE,
        )
        eventually(lambda: health(name) == "healthy", "Container did not become healthy")
        yield name
    except Exception:
        print(docker("logs", name, check=False).stdout, file=sys.stderr)
        print(docker("inspect", "--format", "{{json .State}}", name, check=False).stdout,
              file=sys.stderr)
        raise
    finally:
        docker("rm", "-f", "-v", name, check=False)


def php_fixture(name, filename, source):
    # These probes exist only in a disposable container's writable layer.
    docker("exec", "-i", name, "sh", "-c",
           'cat > "$1"', "sh", "/var/www/baikal/html/" + filename, input=source)


def test_startup_and_permissions():
    with container() as name:
        docker("exec", name, "nginx", "-t")
        docker("exec", name, "php-fpm85", "-t")
        docker("exec", name, "php85", "-r",
               'exit(in_array("pgsql", PDO::getAvailableDrivers(), true) ? 0 : 1);')
        page = docker("exec", name, "wget", "-qO-", "http://127.0.0.1/").stdout
        require("initialization wizard" in page, "Fresh install did not serve its wizard")
        for path in ("", "/html", "/html/index.php", "/vendor", "/Core"):
            docker("exec", "-u", "nginx", name, "sh", "-c",
                   'test ! -w "$1"', "sh", "/var/www/baikal" + path)
        for path in ("Specific", "config"):
            docker("exec", "-u", "nginx", name, "test", "-w", "/var/www/baikal/" + path)
        php_fixture(name, "smoke-log.php",
                    '<?php error_log("baikal-smoke-php-log"); echo "ok";')
        docker("exec", name, "wget", "-qO-", "http://127.0.0.1/smoke-log.php")
        logs = docker("logs", name).stdout
        require("ready to handle connections" in logs, "FPM master logs missing from stderr")
        require("baikal-smoke-php-log" in logs, "PHP application logs missing from stderr")
    print("PASS startup, PostgreSQL driver, permissions, and logging", flush=True)


def test_unresponsive_php():
    with container() as name:
        docker("exec", name, "pkill", "-STOP", "php-fpm85")
        try:
            eventually(lambda: health(name) == "unhealthy",
                       "Health check accepted an unresponsive PHP-FPM")
        finally:
            docker("exec", name, "pkill", "-CONT", "php-fpm85", check=False)
        eventually(lambda: health(name) == "healthy", "Health check did not recover")
    print("PASS health check detects and recovers from stalled PHP-FPM", flush=True)


def test_graceful_shutdown():
    with container() as name:
        php_fixture(name, "smoke-slow.php", '''<?php
file_put_contents('/tmp/smoke-active', 'started');
sleep(6);
file_put_contents('/tmp/smoke-completed', 'finished');
echo 'complete';
''')
        with subprocess.Popen(
            ["docker", "exec", name, "wget", "-qO-", "http://127.0.0.1/smoke-slow.php"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ) as request:
            eventually(lambda: docker("exec", name, "test", "-f", "/tmp/smoke-active",
                                      check=False).returncode == 0,
                       "Slow PHP request did not start")
            docker("stop", "--time", "15", name)
            request.wait(timeout=5)
        require(docker("inspect", "--format", "{{.State.ExitCode}}", name).stdout.strip() == "0",
                "Normal shutdown did not exit successfully")
        # A stopped container retains its filesystem. The marker proves that
        # the active PHP request finished before the container exited.
        result = subprocess.run(
            ["docker", "cp", name + ":/tmp/smoke-completed", "-"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=10,
        )
        require(result.returncode == 0, "Shutdown interrupted the active PHP request")
    print("PASS shutdown drains an active PHP request", flush=True)


def test_service_exit(service, signal):
    with container() as name:
        docker("exec", name, "pkill", "-" + signal, service)
        status = docker("wait", name, timeout=15).stdout.strip()
        require(status == "1", f"Unexpected {service} exit reported container status {status}")
    print(f"PASS unexpected {service} exit ({signal}) fails the container", flush=True)


if __name__ == "__main__":
    test_startup_and_permissions()
    test_unresponsive_php()
    test_graceful_shutdown()
    test_service_exit("php-fpm85", "KILL")
    test_service_exit("nginx", "KILL")
    test_service_exit("nginx", "QUIT")
