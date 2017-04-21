package Net::SSH::Any::Backend::Ssh_Cmd;

use strict;
use warnings;
use Carp;
use Net::SSH::Any::Util qw(_first_defined _array_or_scalar_to_list $debug _debug);
use Net::SSH::Any::Constants qw(SSHA_CHANNEL_ERROR SSHA_REMOTE_CMD_ERROR SSHA_CONNECTION_ERROR);
use parent 'Net::SSH::Any::Backend::_Cmd';

sub _validate_backend_opts {
    my $any = shift;

    $any->SUPER::_validate_backend_opts or return;

    my $be = $any->{be};
    $be->{local_ssh_cmd} //= $any->_find_cmd('ssh',
                                             undef,
                                             { MSWin => 'Cygwin', POSIX => 'OpenSSH' },
                                             '/usr/bin/ssh') // return;
    $any->_set_be_default_friend_cmd($be->{local_ssh_cmd});
    my $out = $any->_local_capture($be->{local_ssh_cmd}, '-V');
    if ($?) {
        $out =~ s/\s+/ /gs; $out =~ s/ $//;
        $any->_set_error(SSHA_CONNECTION_ERROR, 'ssh not found or bad version, rc: '.($? >> 8)." output: $out");
        return;
    }

    my ($auth_type, $interactive_login);

    if (defined $be->{password}) {
        $auth_type = 'password';
        $interactive_login = 1;
        if (my @too_more = grep defined($be->{$_}), qw(key_path passphrase)) {
            croak "option(s) '".join("', '", @too_more)."' can not be used together with 'password'"
        }
    }
    elsif (defined $be->{key_path}) {
        $auth_type = 'publickey';
        if (defined $be->{passphrase}) {
            $auth_type .= ' with passphrase';
            $interactive_login = 1;
        }
    }
    else {
        $auth_type = 'default';
    }

    $any->{be_auth_type} = $auth_type;
    $any->{be_interactive_login} = $interactive_login;
    1;
}

sub _make_cmd {
    my ($any, $cmd_opts, $cmd) = @_;
    my $be = $any->{be};

    my @args = ( $be->{local_ssh_cmd},
                 $be->{host} );
    push @args, '-C';
    push @args, -l => $be->{user} if defined $be->{user};
    push @args, -p => $be->{port} if defined $be->{port};
    push @args, -i => $any->_os_unix_path($be->{key_path}) if defined $be->{key_path};
    push @args, -o => 'BatchMode=yes' unless grep defined($be->{$_}), qw(password passphrase);
    push @args, -o => 'StrictHostKeyChecking=no' unless $be->{strict_host_key_checking};
    push @args, -o => 'UserKnownHostsFile=' . $any->_os_unix_path($be->{known_hosts_path})
        if defined $be->{known_hosts_path};

    if ($any->{be_auth_type} eq 'password') {
        push @args, ( -o => 'PreferredAuthentications=keyboard-interactive,password',
                      -o => 'NumberOfPasswordPrompts=1' );
    }
    else {
        push @args, -o => 'PreferredAuthentications=publickey';
    }

    push @args, '-s' if delete $cmd_opts->{subsystem};
    push @args, '-tt' if delete $cmd_opts->{tty};

    push @args, _array_or_scalar_to_list($be->{ssh_opts})
        if defined $be->{ssh_opts};

    return (@args, '--', $cmd);
}

sub _remap_child_error {
    my ($any, $proc) = @_;
    my $rc = $proc->{rc} // 0;
    if ($rc == (255 << 8)) {
        # A remote command may actually exit with code 255, but it
        # is quite uncommon.
        # SSHA_CONNECTION_ERROR is not recoverable so we use
        # SSHA_CHANNEL_ERROR instead.
	$debug and $debug & 1024 and _debug "child error remaped to channel error";
        $any->_or_set_error(SSHA_CHANNEL_ERROR, "child command exited with code 255, ssh was probably unable to connect to the remote server");
        return
    }
    1;
}

1;
