package Net::SSH::Any::Test::Backend::Cygwin;

use strict;
use warnings;

use Net::SSH::Any;
use Net::SSH::Any::Constants qw(SSHA_BACKEND_ERROR);

use parent 'Net::SSH::Any::Test::Backend::OpenSSH_Daemon';

sub _validate_backend_opts {
    my ($tssh, %opts) = @_;

    $tssh->{be_opts} = \%opts;

    $opts{cygwin_url} //= "http://cygwin.com/setup-x86.exe";
    $opts{cygwin_site} //= "http://mirrors.kernel.org/sourceware/cygwin/";

    1;
}

sub _start_and_check {
    my $tssh = shift;

    my $opts = $tssh->{be_opts};

    my $wdir = $tssh->_backend_wdir;
    my $installer = File::Spec->join($wdir, 'cygwin-setup.exe');
    $tssh->_log("Downloading Cygwin installer to $installer");
    $tssh->_load_module('HTTP::Tiny') or return;
    my $ua = HTTP::Tiny->new;
    my $res = $ua->mirror($opts->{cygwin_url}, $installer);
    unless ($res->{success}) {
        $tssh->_set_error(SSHA_BACKEND_ERROR, "Unable to download Cygwin installer: $res->{status} $res->{reason}");
        return;
    }

    my $rootdir = File::Spec->join($wdir, 'Cygwin');
    $tssh->_run_cmd( {find => 0,
                      name => 'cygwin-installer'},
                     $installer,
                     -R => $rootdir,
                     -s => $opts->{cygwin_site},
                     -P => 'openssh',
                     '-q', '-B', '-n') or return;

    local $ENV{PATH} = "$ENV{PATH};$rootdir\\bin;$rootdir\\sbin";

    $tssh->SUPER::_validate_backend_opts(%$opts) and
        $tssh->SUPER::_start_and_check;
}

1;
