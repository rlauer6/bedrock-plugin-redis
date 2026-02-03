#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;
use English qw(-no_match_vars);

use Scalar::Util qw(reftype);

use Test::More;

use_ok 'BLM::Redis';

our $BLM;
our $CONTEXT = {};

########################################################################
subtest 'new' => sub {
########################################################################
  $BLM = BLM::Redis->new();

  isa_ok( $BLM, 'BLM::Redis' );
};

my $config = { redis => { port => '6379', server => 'localhost' } };

my $options = {};

my %args = (
  params        => [],
  context       => [$CONTEXT],
  config        => $config,
  options       => undef,
  valid_options => [],
);

my $handle = eval {
  ok( $BLM->init_plugin( \%args ), 'init_plugin' );

  return $BLM->handle();
};

########################################################################
subtest 'init_plugin' => sub {
########################################################################

  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  isa_ok( $handle, 'Redis' )
    or BAIL_OUT('handle() did not return a Redis object');

  my $bar = eval {
    $handle->set( 'foo', 'bar' );

    return $handle->get('foo');
  };

  is( $bar, 'bar', 'handle connected' )
    or BAIL_OUT('something is wrong, unable to store keys');
};

########################################################################
subtest 'set/get_key' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle || $EVAL_ERROR;

  $BLM->set_key( 'foo', 'bar' );
  my $bar = $BLM->get_key('foo');

  is( $bar, 'bar', 'got a scalar' );

  my $popo = { foo => 'bar', baz => { biz => 'buz' } };

  $BLM->set_key( 'popo', $popo );

  my $obj = $BLM->get_key('popo');

  is_deeply( $obj, $popo, 'got a popo' )
    or diag( Dumper( [ popo => $popo ] ) );

};

########################################################################
subtest 'expire' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  $BLM->set_key( 'foo', 'bar', 2 );

  my $bar = $BLM->get_key('foo');

  is( $bar, 'bar', 'got a scalar' );
  sleep 1;

  my $metadata = $BLM->metadata('foo');

  ok( $metadata->{expire} == 1, 'metadata updated' );

  sleep 2;

  ok( !$BLM->get_key('foo'), 'key expired' );
};

########################################################################
subtest 'storable' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  my $popo = $BLM->get_key('popo');

  $BLM->set_key( 'bedrock_hash', bless $popo, 'Bedrock::Hash' );

  my $obj = $BLM->get_key('bedrock_hash');

  is_deeply( $obj, $popo, 'stored blessed object' );

  $BLM->storable(1);

  $BLM->set_key( 'bedrock_hash', bless $popo, 'Bedrock::Hash' );

  $obj = $BLM->get_key('bedrock_hash');

  isa_ok( $obj, 'Bedrock::Hash' )
   or diag( Dumper( [ keys => $obj->keys() ] ) );
};

########################################################################
subtest 'raw' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  my $raw = $BLM->get_key( 'popo', raw => 1 );

  ok( !ref $raw, 'retrieved raw popo' );

  my $obj = eval { return JSON->new->decode($raw); };

  isa_ok( $obj, 'HASH', 'decoded metadata' )
    or BAIL_OUT( 'unable to decode metadata ' . $EVAL_ERROR );

  foreach (qw(timestamp md5 value method)) {
    ok( defined $obj->{$_}, $_ . ' present in hash' );
  }

  my $value = eval { return JSON->new->decode( $obj->{value} ); };

  ok( ref $value, 'decoded value' );

  is_deeply( $value, $BLM->get_key('popo'), 'decoded value is same as get_key' );

  like( $obj->{timestamp}, qr/^\d+$/xsm, 'timestamp looks like timestamp' );

  like( $obj->{md5}, qr/^[a-f\d]+$/xsm, 'md5 looks like an md5 hash' );
};

########################################################################
subtest 'export' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  $BLM->export('popo');

  is_deeply( $CONTEXT->{popo}, $BLM->get_key('popo'), 'export(key) - exported object' );

  my $pep_boyz = [qw(manny moe jack)];

  $BLM->export( 'pep_boyz', $pep_boyz );

  is_deeply( $CONTEXT->{pep_boyz}, $pep_boyz, 'export(key, value) - exported object' );

  $BLM->export_keys(1);

  my $stooges = [qw(larry moe curly shemp joe)];
  $BLM->set_key( 'stooges', $stooges );

  $BLM->get_key('stooges');

  is_deeply( $CONTEXT->{stooges}, $stooges, 'auto export' );
};

########################################################################
subtest 'metadata' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  my $metadata = $BLM->metadata('stooges');

  isa_ok( $metadata, 'HASH' );

  foreach (qw(timestamp md5 value method)) {
    ok( defined $metadata->{$_}, $_ . ' present in hash' );
  }
};

########################################################################
subtest 'last_modified' => sub {
########################################################################
  plan skip_all => 'skipping...could not connect to Redis server'
    if !$handle;

  my $last_modified = $BLM->last_modified('stooges');

  # Sun, 19 Jan 2025 14:40:24 GMT
  like( $last_modified, qr/^(sun|mon|tue|wed|thu|fri|sat),\s\d{1,2}\s/xsmi, 'formatted last modified date' );

  diag($last_modified);
};

done_testing;

1;

__END__
