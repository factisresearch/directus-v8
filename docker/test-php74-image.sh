#!/bin/sh
# Standalone smoke test for a Directus 8 image running patched PHP 7.4.33.
# Requires Docker and an already built image; no local PHP installation is needed.
# Usage: sh docker/test-php74-image.sh [image-name]
# Override DOCKER_PLATFORM to test an architecture other than linux/amd64.
#
# Security checks:
# - CVE-2026-109618 (RCE through out-of-memory corruption): checks the PHP 7.4
#   backport's immediate process termination on memory exhaustion, including
#   exit status and suppression of shutdown callbacks. This tests the mitigation
#   behavior in CLI PHP, not the vulnerable HTTP request or an RCE exploit.
# - Checks max_multipart_body_parts in CLI and Apache PHP as a backport marker.
#   Its presence alone does not prove either CVE is fixed.
# Advisory: https://www.php.net/archive/2026.php#2026-10-21-5
#
# Functional coverage:
# - Exact PHP version, loaded extensions and representative Composer classes.
# - Apache configuration validation and startup through the Directus entrypoint.
# - Static admin HTML delivery and PHP execution through Apache's mod_php.
# - Presence of the example configuration after volume initialization.
#
# Not covered:
# - CVE-2026-109619 (RCE through stale global state): no dedicated regression
#   test is included. This script does not exercise state reuse between requests
#   in the same worker and cannot establish that this CVE is fixed.
# - Complete exploit regression tests for either CVE.
# - Multipart limit enforcement and session upload-progress behavior.
# - Database access, login, uploads, Redis/S3 connections and browser-side admin
#   JavaScript.
#
# Prints PASS for completed groups and exits nonzero on a failed assertion or
# unexpected command error. Test data is confined to a disposable container.

# Stop on unexpected command failures and references to unset variables.
set -eu

# Run in a disposable container with a 512 MB memory limit. External networking
# is disabled; loopback remains available for the Apache HTTP checks below.
# No host directories are mounted and no ports are published. --rm removes the
# container and its anonymous volumes, including temporary test files, on exit.
# Start a shell instead of the normal entrypoint so checks can run first, then
# pass the quoted heredoc through stdin without expanding it in the host shell.
docker run --rm -i --platform "${DOCKER_PLATFORM:-linux/amd64}" \
    --network none --memory 512m --entrypoint sh \
    "${1:-medilyse/directus-v8:php74-patched}" <<'CHECK'
set -eu

# Test 1: Runtime dependencies and backport marker.
# Check the CLI runtime, the directive introduced by the backport and the
# extensions required by the application. The version alone cannot identify
# the patch: both patched and unpatched builds report PHP 7.4.33.
# Load representative classes through Composer to catch missing packages or
# broken vendor symlinks. This does not connect to any external services.
php -r '
if (PHP_VERSION !== "7.4.33") { throw new RuntimeException("Unexpected PHP version"); }
if (ini_get("max_multipart_body_parts") === false) { throw new RuntimeException("Missing backport directive"); }
foreach (["gd", "zip", "exif", "pdo_mysql", "mysqli", "imagick", "redis", "curl", "mbstring"] as $ext) {
    if (!extension_loaded($ext)) { throw new RuntimeException("Missing extension: ".$ext); }
}
require "/var/directus/vendor/autoload.php";
foreach (["Directus\\Application\\Application", "Zend\\Db\\Adapter\\Adapter", "Cache\\Adapter\\Filesystem\\FilesystemCachePool", "League\\Flysystem\\AwsS3v3\\AwsS3Adapter"] as $class) {
    if (!class_exists($class)) { throw new RuntimeException("Missing class: ".$class); }
}
echo "PHP version, extensions and application autoload: PASS\n";
'

# Test 2: CVE-2026-109618 backport behavior on memory exhaustion.
# Deliberately exceed PHP's own memory limit in a separate process. The patched
# runtime must terminate immediately with status 1 and a memory-limit error,
# without invoking the registered shutdown callback. The container's 512 MB
# limit is separate from this 4 MB PHP limit; we are testing PHP's error path,
# not termination by the operating system's out-of-memory killer.
# Temporarily allow a failing command so its expected exit code can be checked.
set +e
out=$(php -d memory_limit=4M -r 'register_shutdown_function(function () { echo "SHUTDOWN\n"; }); str_repeat("a", 64 * 1024 * 1024);' 2>&1)
code=$?
set -e
test "$code" -eq 1
echo "$out" | grep -q 'Allowed memory size'
if echo "$out" | grep -q SHUTDOWN; then exit 1; fi
echo 'Patched OOM behavior: PASS'

# Test 3: Apache configuration syntax.
# Validate Apache configuration before attempting to start the server.
apache2ctl -t

# Test 4: Entrypoint startup, admin HTTP response, mod_php and seeded config.
# Exercise the real entrypoint, including volume seeding, with disposable auth
# keys that satisfy its startup checks. These are test values, not credentials
# for an existing installation. Create a temporary endpoint to inspect PHP as
# executed by Apache, independently of the CLI checks above.
printf '%s\n' '<?php echo PHP_VERSION, "|", PHP_SAPI, "|", ini_get("max_multipart_body_parts");' > /var/directus/public/__php74_smoke.php
export DIRECTUS_AUTH_SECRETKEY=smoke-test-secret-key
export DIRECTUS_AUTH_PUBLICKEY=smoke-test-public-key
directus-entrypoint apache2-foreground >/tmp/apache-smoke.log 2>&1 &
server=$!
# Stop the background server when this test shell exits, including on failure.
trap 'kill "$server" 2>/dev/null || true' EXIT

# Retry the static admin request up to ten times while Apache starts. If it
# never succeeds, print the server log to help diagnose the startup failure.
ready=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --fail --silent http://127.0.0.1/admin/ -o /tmp/admin.html; then ready=true; break; fi
    sleep 1
done
if [ "$ready" != true ]; then cat /tmp/apache-smoke.log; exit 1; fi
# Check that the admin route returns HTML; this does not run its JavaScript.
grep -qi '<html' /tmp/admin.html
# Verify Apache uses PHP 7.4.33 through mod_php and exposes the new directive
# with its default value (-1). Merely finding a patched CLI binary is not enough.
test "$(curl --fail --silent http://127.0.0.1/__php74_smoke.php)" = '7.4.33|apache2handler|-1'
# Check that the example configuration is present after volume initialization.
test -f /var/directus/config/_example.php
echo 'Entrypoint, mod_php and admin HTTP route: PASS'
CHECK
