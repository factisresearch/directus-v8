<?php

// Prepare the legacy API dependencies for the PHP 7.4 Docker build.
// The API has no committed composer.lock, and some of its development-branch
// requirements no longer resolve to PHP 7.4-compatible packages today.
// Dockerfile.local runs this script from /build/api before composer install.
// Only the manifest copied into the build stage is changed; the checkout stays
// untouched. This script prepares metadata, but does not install any packages.
$manifest = json_decode(file_get_contents('/build/api/composer.json'), true);

// Dockerfile.local copies this lockfile from the pinned historical Directus
// image. Use it as a source of package metadata, not as the API's entire lockfile:
// the current checkout and its local packages still need dependency resolution.
$lock = json_decode(file_get_contents('/tmp/legacy-composer.lock'), true);

// The API requires cache/cache at dev-master, whose current branch requires
// PHP 8.2. Recover the historical package entry, including its source/dist
// references and dependency requirements, to select the older compatible code.
$cache = null;
foreach ($lock['packages'] as $package) {
    if ($package['name'] === 'cache/cache') {
        $cache = $package;
        break;
    }
}
if ($cache === null) {
    // Stop rather than silently fall back to the incompatible current branch.
    throw new RuntimeException('The legacy lock must contain cache/cache.');
}

// Local Directus packages are provided through Composer path repositories.
// Their relative paths resolve from /build/api to /build/packages.
foreach ($manifest['repositories'] as &$repository) {
    if ($repository['type'] === 'path') {
        $local = json_decode(file_get_contents($repository['url'] . '/composer.json'), true);

        // The Docker context excludes .git, so Composer cannot infer the branch
        // version from Git and may assign dev-main. Explicitly expose dev-master
        // to satisfy the legacy requirements without changing package sources.
        $repository['options']['versions'][$local['name']] = 'dev-master';

        // Copy package files into vendor instead of linking to /build/packages.
        // That build-stage directory is absent from the final runtime image,
        // so symlinks would leave the installed application with missing code.
        $repository['options']['symlink'] = false;
    }
}
unset($repository);

// Search the historical package definition before other repositories so that
// cache/cache resolves to the recovered reference rather than today's branch.
array_unshift($manifest['repositories'], ['type' => 'package', 'package' => $cache]);

// Preserve the S3 support added by the original Docker build. Keep the adapter
// on Flysystem 1.x, matching this application's filesystem integration.
$manifest['require']['aws/aws-sdk-php'] = '^3.0';
$manifest['require']['league/flysystem-aws-s3-v3'] = '^1.0';

// Write the temporary manifest for the subsequent composer install step.
// This does not freeze every dependency: apart from the recovered cache/cache
// reference, Composer still resolves versions from the manifest's constraints.
file_put_contents('/build/api/composer.json', json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
