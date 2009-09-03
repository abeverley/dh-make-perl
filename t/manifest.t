#!/usr/bin/perl -w

use Test::More;

if(!$ENV{RELEASE_TESTING}) {
  plan skip_all => 'Test::DistManifest only happens for RELEASE_TESTING';
}

eval 'use Test::DistManifest';
if ($@) {
  plan skip_all => 'Test::DistManifest required to test MANIFEST';
}

manifest_ok();