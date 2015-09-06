package ZooKeeper::PathCache;

use List::MoreUtils qw(uniq);
use Safe::Isa qw($_isa);
use Scalar::Util qw(weaken);
use Try::Tiny;
use ZooKeeper;
use ZooKeeper::Constants;
use ZooKeeper::Error;
use Moo;
use namespace::autoclean -also => qr/^__/;
with 'Backbone::Events';

# ABSTRACT: cache all immediate children of a parent node

=head1 DESCRIPTION

ZooKeeper::PathCache is a facade over a ZooKeeper handle,
used for caching the contents of all immediate children nodes
of the specified path.

This works by including a version number in the path of child nodes,
so that one watcher can be set to monitor version changes in any child.

=head1 ATTRIBUTES

=head2 handle

=cut

has handle => (
    is     => 'ro',
    isa    => sub { shift->$_isa('ZooKeeper') },
    coerce => \&_to_handle,
);
sub _to_handle {
    my ($args) = @_;
    if ($args->$_isa('ZooKeeper')) {
        return $args;
    } else {
        return ZooKeeper->new($args);
    }
}

=head2 path

=cut

has path => (
    is       => 'ro',
    required => 1,
);

=head2 serialize

=cut

sub __identity { $_[1] }

has _serialize => (
    is       => 'ro',
    init_arg => 'serialize',
    default  => sub { \&__identity },
);
sub serialize {
    my ($self, @args) = @_;
    return $self->_serialize->($self, @args);
}

=head2 deserialize

=cut

has _deserialize => (
    is       => 'ro',
    init_arg => 'deserialize',
    default  => sub { \&__identity },
);
sub deserialize {
    my ($self, @args) = @_;
    return $self->_deserialize->($self, @args);
}

has _cache => (
    is      => 'ro',
    default => sub { {} },
);

sub _ensure_exists {
    my ($self, $node) = @_;
    return if $self->handle->exists($node);

    my ($parent) = $node =~ m#(.+)/[^/]+#;
    if ($parent and not $self->handle->exists($parent)) {
        $self->_ensure_exists($parent);
        $self->handle->create($parent);
    }

    if (not $self->handle->exists($node)) {
        $self->handle->create($node);
    }
}

sub __parse {
    my ($node) = @_;
    my ($version, $key) = split('#', $node, 2) or return;
    return wantarray ? ($key, $version) : $key;
}

sub _format {
    my ($self, $key, $version) = @_;
    return $self->path."/$version#$key";
}

sub _get_nodes {
    my ($self) = @_;
    return $self->handle->get_children($self->path);
}

sub _get_versions {
    my ($self) = @_;
    my %versions;
    for my $node ($self->_get_nodes) {
        my ($key, $version) = __parse($node) or next;
        my $seen = $versions{$version};
        next if defined $seen and $seen > $version;
        $versions{$key} = $version;
    }
    return %versions;
}

sub _assert {
    my ($self, $key, $version) = @_;
    my %versions = $self->_get_versions;
    my $newest   = $versions{$key};
    
    my $error;
    $error = ZNONODE     if not defined $newest;
    $error = ZBADVERSION if $newest != $version;
    ZooKeeper::Error->throw(code => $error) if defined $error;
}

sub _add_key {
    my ($self, $key, $version, $value) = @_;
    if (@_ == 3) {
        my $node   = $self->_format($key, $version);
        my $_value = $self->handle->get($node);
        $value     = $self->deserialize($_value);
    }
    return $self->_cache->{$key} = {
        value   => $value,
        version => $version,
    };
}

=head1 METHODS

=head2 create

=cut

sub create {
    my ($self, $_key, %opts) = @_;
    my $value      = $opts{value} // '';
    my $serialized = $self->serialize($value);

    my $_node = $self->_format($_key, 0);
    my $node  = $self->handle->create($_node, %opts, value => $serialized);
    my $key   = __parse($node);

    try {
        $self->_assert($key, 0);
    } catch {
        $self->handle->delete($node) if $_ == ZBADVERSION;
        $_->throw;
    };

    $self->_add_key($key, 0, $value);
    return $key;
}

=head2 delete

=cut

sub delete {
    my ($self, $key, %opts) = @_;
    ZooKeeper::Error->throw(code => ZNONODE) unless $self->exists($key);
    my $version = $self->_cache->{$key}{version};
    my $node    = $self->_format($key, $version);
    $self->handle->delete($node);
    delete $self->_cache->{$key};
}

=head2 set

=cut

sub set {
    my ($self, $key, $value, %opts) = @_;
    ZooKeeper::Error->throw(code => ZNONODE) unless $self->exists($key);
    my $version    = $self->_cache->{$key}{version};
    my $old        = $self->_format($key, $version);
    my $new        = $self->_format($key, $version + 1);
    my $serialized = $self->serialize($value);

    my ($result) = $self->handle->transaction
                                ->delete($old)
                                ->create($new, value => $serialized)
                                ->commit;
    if ($result->{type} eq 'error') {
        my $error;
        my %versions = $self->_get_versions;
        if (exists $versions{$key}) {
            $error = ZBADVERSION;
        } else {
            $error = ZNONODE;
        }
        ZooKeeper::Error->throw(code => $error);
    }

    $self->_add_key($key, $new, $value);
}

=head2 get

=cut

sub get {
    my ($self, $key) = @_;
    my $cached = $self->_cache->{$key} or ZooKeeper::Error->throw(code => ZNONODE); 
    return $cached->{value};
}

=head2 get_children

=cut

sub get_children {
    my ($self) = @_;
    return keys %{$self->_cache};
}

=head2 exists

=cut

sub exists {
    my ($self, $key) = @_;
    return exists $self->_cache->{$key};
}

=head2 sync

=cut

sub sync {
    my ($self) = @_;
    my %cached = map {($_ => $self->_cache->{$_}{version})} $self->get_children;
    my %recent = $self->_get_versions;

    for my $key (uniq keys(%cached), keys(%recent)) {
        if (not exists $recent{$key}) {
            my $old = delete $self->_cache->{$key};
            $self->trigger("$key:delete", $old);
        } elsif (not exists $cached{$key}) {
            my $new = $self->_add_key($key, $recent{$key});
            $self->trigger("$key:create", $new);
        } elsif ($cached{$key} != $recent{$key}) {
            my $old = $self->_cache->{$key};
            my $new = $self->_add_key($key, $recent{$key});
            $self->trigger("$key:set", $new, $old);
        }
    }
}

sub _watch {
    my ($self, $dir) = @_;
    weaken($self);
    $self->handle->get_children($dir, watcher => sub {
        $self->sync;
        $self->_watch($dir);
    });
}

sub BUILD {
    my ($self) = @_;
    $self->sync;
    $self->_watch($self->path);
}

1;
