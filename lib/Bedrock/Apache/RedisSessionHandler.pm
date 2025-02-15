package Bedrock::Apache::RedisSessionHandler;

use strict;
use warnings;

use Apache2::RequestRec ();  # $r
use Apache2::Connection ();  # $r->connection
use APR::Table          ();  # $r->headers_in

use Apache2::Const -compile => qw(OK
  DECLINED
  FORBIDDEN
  REDIRECT
  HTTP_NOT_FOUND
  HTTP_INTERNAL_SERVER_ERROR
  AUTH_REQUIRED
);

use Redis;

use Role::Tiny::With;
with 'Bedrock::Role::RedisClient';

use Bedrock::XML;
use Bedrock::Constants qw(:booleans :chars);

use Data::Dumper;

use English qw(-no_match_vars);

########################################################################
sub redirect {
########################################################################
  my ($r) = @_;

  my $login_url = redis_config()->{config}->{login_url} // '/index.html';

  $r->headers_out->{Location} = $login_url;

  $r->log->debug( 'redirecting to ', $login_url );

  return Apache2::Const::REDIRECT;
}

########################################################################
sub is_session_valid {
########################################################################
  my ($r) = @_;

  my $cookie = $r->headers_in->{Cookie};

  $r->log->debug( 'cookie: ' . $cookie // $EMPTY );

  return
    if !$cookie;

  my $session_id;

  if ( $cookie =~ /session=(\w*)/xsm ) {
    $session_id = $1;

    $r->log->debug( 'found a session cookie: ' . $session_id );
  }

  my $session_key = redis_key($session_id);

  my $redis = redis_handle();

  return
    if !$redis->exists($session_key);

  $r->log->debug( 'found a session: ' . Dumper($session_key) );

  my $session = redis_session($session_key);

  return
    if !$session;

  $r->log->debug( 'found an active session' . Dumper($session_key) );

  my $username = redis_config()->{config}->{username};

  return $session->{$username};
}

########################################################################
sub handler {
########################################################################
  my ($r) = @_;

  if ( is_session_valid($r) ) {
    return Apache2::Const::OK;
  }
  else {
    return redirect($r);
  }
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 NAME

Apache::RedisSessionHandler - Session validation for a Redis session manager

=head1 SYNOPSIS

 <Directory /var/www/html/foo >
   PerlHeaderParserHandler Bedrock::Apache::RedisSessionHandler>
 </Directory>

=head1 DESCRIPTION

Provides an Apache authorization layer that checks to see if a user
has been authenticated. Authenticated in the context of this module,
simply means that the user has a session cookie and the session cookie
can be used to validate the session. A valid session is one in which
the session contains the user's name.  The user's name should be
stored in a session key whose name is configured in the F<redis.xml>
configuration file (C<username>).

 <!-- Bedrock RedisSessions -->
 <object>
   <scalar name="binding">session</scalar>
   <scalar name="session">yes</scalar>
   <scalar name="module">BLM::Startup::RedisSession</scalar>
 
   <object name="config">
     <scalar name="verbose">2</scalar>
     <scalar name="param">session</scalar>
 
     <scalar name="server">172.25.0.1</scalar>
     <scalar name="port">6379</scalar>
     <scalar name="login_url">/login.roc</scalar>
     <scalar name="username">login_name</scalar>
 
     <object name="cookie">
       <scalar name="path">/</scalar>
       <scalar name="expiry_secs">3600</scalar>
       <scalar name="domain"></scalar>
     </object>
   </object>
 </object>

This module does not authenticate users. It determines if a user has
been authenticated and either redirects the user to a location that
allows them to authenticate (C<login_url>) or returns an OK status if
they have already been logged in.

=head1 AUTHOR

Rob Lauer - rclauer@gmail.com

=head1 SEE OTHER

L<Bedrock::RedisClient>, L<BLM::Startup::RedisSession>, L<Redis>

=cut
