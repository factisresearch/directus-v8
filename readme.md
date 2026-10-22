<p align="center">
  <a href="https://directus.io" target="_blank" rel="noopener noreferrer">
    <img src="https://user-images.githubusercontent.com/522079/43096167-3a1b1118-8e86-11e8-9fb2-7b4e3b1368bc.png" width="140" alt="Directus Logo"/>
  </a>
</p>

<p>&nbsp;</p>

<h1 align="center">
  This end-of-life version of Directus has been deprecated and is superseded by the latest version on <a href="https://github.com/directus/directus">directus/directus</a>. Learn more about the updates and improvements of our new version at <a href="https://directus.io">directus.io</a>.
</h1>

<p>&nbsp;</p>

> _Our Core team is quite small and can not maintain legacy versions of Directus. We'll glady review any community pull-requests to this repository, but using this version is highly discouraged._

<p>&nbsp;</p>

## Purpose of this fork

This fork addresses the critical PHP
vulnerabilities **CVE-2026-109618** and **CVE-2026-109619**, with the minimum
application changes needed to build and run the patched runtime.

It is not a commitment to maintain Directus 8 long-term or migrate it to PHP 8.
Directus 8 and PHP 7.4 remain end-of-life. The build uses PHP 7.4.33 with the
[official PHP source backport](https://www.php.net/archive/2026.php#2026-10-21-5)
provided for these vulnerabilities, packaged in a third-party Apache image.

The fork's build is defined in [docker/Dockerfile.local](docker/Dockerfile.local).
The original [Apache Dockerfile](docker/images/apache/Dockerfile) and historical
build scripts remain unchanged and do not include these fixes.

## Build with Docker

From the repository root, run:

```sh
docker build --platform linux/amd64 --progress=plain \
  -f docker/Dockerfile.local -t meqo/directus-v8:php74-patched .
```

No local PHP, Composer, Node.js or Yarn installation is required. The build
compiles `app/` with Node 14 and Yarn's frozen lockfile, installs `api/` and the
local packages with Composer 2.2, and combines them in the final image.

The PHP 7.4.33/Apache runtime comes from
[`mpyw/php-eol-CVE-2026-109618-109619` v1.1.0](https://github.com/mpyw/php-eol-CVE-2026-109618-109619/releases/tag/v1.1.0),
pinned to digest `sha256:84e87ad92400dfa7ae66aa475a5ccdc4d9c90e87e81f97ceb652c54a35b43d90`.
It includes the official PHP backport
[`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2`](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)
for CVE-2026-109618 and CVE-2026-109619. PHP still reports version `7.4.33`;
the version string alone does not identify the patched build.

GD, ZIP, EXIF, PDO-MySQL, MySQLi, Imagick 3.7.0 and Redis 5.3.7 are built in
Docker. The existing Directus Apache configuration, entrypoint, environment
variables and volume seeding are retained. PHP remains end-of-life; this change
targets the two CVEs, not general modernization.

The backport exits the worker immediately on out-of-memory errors, without
running shutdown callbacks. It also disables PHP session upload progress and
adds `max_multipart_body_parts` (default: `max_input_vars + max_file_uploads`).
Normal application login and upload behavior still needs testing against a
representative database before deployment.

The build-stage Composer manifest uses the `cache/cache` package metadata from
the old, separately pinned Directus image's lockfile because today's `dev-master`
requires PHP 8.2. Only that lockfile is copied into the build stage; no PHP 7.3
runtime or application files are inherited. Local path
packages are explicitly labelled `dev-master` and copied rather than symlinked.
The S3 dependencies from the original Dockerfile are included. These adjustments
do not modify `api/composer.json` in the checkout. Other PHP dependencies are
resolved at build time; the resulting `composer.lock` is included in the image.

Local configuration, uploads, logs, `.env` files and installed dependencies are
excluded from this build context. Configure the resulting container using the
existing environment variables and volumes. The build does not start a database
or deploy the application.

To run the isolated image smoke checks (no database or published ports):

```sh
sh docker/test-php74-image.sh meqo/directus-v8:php74-patched
```

The smoke test checks PHP and extension availability, Composer autoloading,
Apache startup, static admin HTML delivery and PHP execution through mod_php.
For CVE-2026-109618 it checks immediate termination on memory exhaustion
without shutdown callbacks. It does not contain a dedicated regression test
for CVE-2026-109619 or a complete exploit test for either CVE.

----

<p align="center">
  Directus is released under the <a href="http://www.gnu.org/copyleft/gpl.html">GPLv3</a> license. <a href="http://rangerstudio.com">RANGER Studio LLC</a> owns all Directus trademarks and logos on behalf of our project's community. Copyright © 2006-2020, <a href="http://rangerstudio.com">RANGER Studio LLC</a>.
</p>

