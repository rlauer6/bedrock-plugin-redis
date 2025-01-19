package Faux::Context;

use strict;
use warnings;

########################################################################
sub new {
########################################################################
  my ( $class, %options ) = @_;

  my $self = bless \%options, $class;

  return $self;
}

########################################################################
sub cgi_header_in    { }
sub send_http_header { }
sub cgi_header_out   { }
########################################################################

########################################################################
sub getCookieValue {
########################################################################
  my ( $self, $name ) = @_;

  return $ENV{$name};
}

########################################################################
sub getInputValue {
########################################################################
  my ( $self, $name ) = @_;

  return $ENV{$name};
}

########################################################################
package main;
########################################################################

use strict;
use warnings;

use Bedrock qw(slurp_file);

use Bedrock::Handler qw(bind_module);
use Bedrock::BedrockConfig;
use Bedrock::Constants qw(:defaults :chars :booleans);
use Bedrock::XML;
use Cwd;
use Data::Dumper;
use DBI;
use English qw(-no_match_vars);
use File::Temp qw(tempfile tempdir);
use Digest::SHA qw(sha256_hex);

use BLM::Startup::RedisSession;

use Test::More;

########################################################################
sub get_module_config {
########################################################################
  my $fh = *DATA;

  my $config = Bedrock::XML->new($fh);
  my ( undef, $filename ) = tempfile( TEMPLATE => 'XXXXXX', UNLINK => $TRUE );

  my $session_config = $config->{config};

  $session_config->{cookieless_sessions} = $TRUE;

  return $session_config;
}

my $module_config = get_module_config;

my $ctx = Faux::Context->new( CONFIG => { SESSION_DIR => tempdir( CLEANUP => 1 ) } );

my $session = eval {
  return bind_module(
    context => $ctx,
    config  => $module_config,
    module  => 'BLM::Startup::RedisSession'
  );
};

plan skip_all => 'no Redis server'
  if $EVAL_ERROR && $EVAL_ERROR =~ /connect/xsm;

ok( !$EVAL_ERROR, 'bound module' )
  or BAIL_OUT($EVAL_ERROR);

isa_ok( $session, 'BLM::Startup::RedisSession' )
  or do {
  diag( Dumper( [$session] ) );
  BAIL_OUT('session is not instantiated properly');
  };

########################################################################
subtest 'session id' => sub {
########################################################################
  ok( $session->{session}, 'session id exists' );

  like( $session->{session}, qr/^[\da-f]{32}$/xsm, 'session is a md5 hash' );
};

########################################################################
subtest 'create_session_dir' => sub {
########################################################################
  my $session_dir = $session->create_session_dir;

  ok( $session_dir, 'create_session_dir() - returns a directory' );

  ok( -d $session_dir, 'create_session_dir() - directory exists' );

  ok( -w $session_dir, 'create_session_dir() - session is writeable' );
};

########################################################################
subtest 'create_session_file' => sub {
########################################################################
  my $file = $session->create_session_file( 'test.jroc', $module_config );

  ok( -s $file, 'file written' );

  my $obj = eval {
    require JSON;

    my $content = slurp_file $file;

    return JSON->new->decode($content);
  };

  is_deeply( $obj, $module_config, 'object serialized correctly' )
    or diag( Dumper( [ $obj, $module_config ] ) );

  unlink $file;

  my $session_dir = $session->create_session_dir;

  rmdir $session_dir;
};

my $session_id = $session->{session};

########################################################################
subtest 'close' => sub {
########################################################################
  $session->{foo} = 'bar';

  eval { return $session->closeBLM; };

  ok( !$EVAL_ERROR, 'closeBLM' )
    or diag( Dumper( [$EVAL_ERROR] ) );
};

########################################################################
subtest 'save' => sub {
########################################################################
  $ENV{session} = $session_id;

  $session = eval {
    return bind_module(
      context => $ctx,
      config  => $module_config,
      module  => 'BLM::Startup::RedisSession'
    );
  };

  is( $session->{foo}, 'bar', 'session saved' )
    or diag( Dumper( [$session] ) );
};

########################################################################
subtest 'login' => sub {
########################################################################

  my $salt = sha256_hex('Yabba dabba doo!');

  my $password = 'W1lma';

  my $salted_password = $salt . sha256_hex( $salt . $password );

  my $users = [
    { username  => 'fflintstone',
      password  => $salted_password,
      firstname => 'Fred',
      lastname  => 'Flintstone',
      email     => 'fflintstone@openbedrock.org',
    }
  ];

  $session->load_users($users);

  my $retval = eval { return $session->login( 'fflintstone', $password ); };

  ok( !$EVAL_ERROR, 'successful login' )
    or diag( Dumper( [ error => $EVAL_ERROR ] ) );

};

########################################################################
subtest 'logout' => sub {
########################################################################
  my $session_id = $session->{session};

  $session->logout();

  ok( !$session->{username}, 'logout' )
    or diag( Dumper( [ session => $session ] ) );
};

########################################################################
subtest 'remove_users' => sub {
########################################################################
  $session->remove_user('fflintstone');

  my $users = $session->fetch_users();

  isa_ok( $users, 'HASH' );

  ok( !keys %{$users}, 'no more users' );

};

########################################################################
subtest 'register' => sub {
########################################################################
  $session->register( 'wflintstone', 'FredB1rd', 'Wilma', 'Flinstone', 'wflinstone@openbedrock.org' );

  my $users = $session->fetch_users();

  isa_ok( $users, 'HASH' );

  ok( keys %{$users}, '1 user registered' );

  $session->login( 'wflintstone', 'FredB1rd' );
  diag( Dumper( [ session => $session ] ) );
};

########################################################################

done_testing;

########################################################################
END {

}

1;

__DATA__
<object>
  <scalar name="binding">session</scalar>
  <scalar name="session">yes</scalar>
  <scalar name="module">BLM::Startup::RedisSession</scalar>

  <object name="config">
    <scalar name="verbose">0</scalar>
    <scalar name="param">session</scalar>
    <scalar name="foo">foo</scalar>

    <!-- Redis connect information -->
    <scalar name="server">localhost</scalar>
    <scalar name="port">6379</scalar>
    <scalar name="login_url">/login.roc</scalar>
    <scalar name="username">username</scalar>

    <object name="cookie">
      <scalar name="path">/</scalar>
      <scalar name="expiry_secs">3600</scalar>
      <scalar name="domain"></scalar>
    </object>
  </object>
</object>
9
