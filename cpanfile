requires 'namespace::autoclean', '0.16';
requires 'Backbone::Events';
requires 'List::MoreUtils';
requires 'Moo';
requires 'Safe::Isa';
requires 'Scalar::Util';
requires 'Try::Tiny';
requires 'ZooKeeper', '0.1.0';

on develop => sub {
    requires 'Dist::Zilla::Plugin::ExtraTests';
    requires 'Dist::Zilla::Plugin::GitHub::Meta';
    requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
    requires 'Dist::Zilla::Plugin::ReadmeFromPod';
    requires 'Dist::Zilla::PluginBundle::Basic';
    requires 'Pod::Markdown';
    requires 'Test::Pod';
};

on test => sub {
    requires 'Test::Class::Moose', '0.55';
    requires 'Test::Strict';
};
