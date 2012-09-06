package File::Truncate::Undoable;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::Trash::Undoable;

# VERSION

our %SPEC;

$SPEC{truncate} = {
    v           => 1.1,
    summary     => 'Truncate a file, with undo support',
    description => <<'_',

On do, will trash file then create an empty file (with the same permission and
ownership as the original). On undo, will trash the new file and untrash the old
file.

Note: chown will not be done if we are not running as root. Symlink is currently
not permitted.

Fixed state: file exists and size is not zero.

Fixable state: file exists and size is not zero.

Unfixable state: file does not exist or path is not a regular file (directory
and symlink included).

_
    args        => {
        path => {
            schema => 'str*',
            req    => 1,
            pos    => 0,
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub truncate {
    my %args = @_;

    # TMP, schema
    my $tx_action  = $args{-tx_action} // '';
    my $taid       = $args{-tx_action_id}
        or return [400, "Please specify -tx_action_id"];
    my $dry_run    = $args{-dry_run};
    my $path       = $args{path};
    defined($path) or return [400, "Please specify path"];

    my $is_sym  = (-l $path);
    my @st      = stat($path);
    my $exists  = $is_sym || (-e _);
    my $is_file = (-f _);
    my $is_zero = !(-s _);

    if ($tx_action eq 'check_state') {
        return [412, "File $path does not exist"]        unless $exists;
        return [500, "File $path can't be stat'd"]       unless @st;
        return [412, "File $path is not a regular file"] if $is_sym||!$is_file;
        return [304, "File $path is already truncated"]  if $is_zero;

        $log->info("(DRY) Truncating file $path ...") if $dry_run;
        return [200, "File $path needs to be truncated", undef,
                {undo_actions=>[
                    ['File::Trash::Undoable::untrash',
                     {path=>$path, suffix=>substr($taid,0,8)}], # restore orig
                    ['File::Trash::Undoable::trash',
                     {path=>$path, suffix=>substr($taid,0,8)."n"}], # trash new
                ]}];
    } elsif ($tx_action eq 'fix_state') {
        $log->info("Truncating file $path ...");
        my $res = File::Trash::Undoable::trash(
            -tx_action=>'fix_state', path=>$path, suffix=>substr($taid,0,8));
        return $res unless $res->[0] == 200 || $res->[0] == 304;
        open my($fh), ">", $path or return [500, "Can't create: $!"];
        chmod $st[2] & 07777, $path; # ignore error?
        unless ($>) { chown $st[4], $st[5], $path } # XXX ignore error?
        return [200, "OK"];
    }
    [400, "Invalid -tx_action"];
}

1;
# ABSTRACT: Truncate a file, with undo support

=head1 SEE ALSO

L<Rinci::Transaction>

=cut
