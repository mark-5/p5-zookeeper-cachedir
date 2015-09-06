# NAME

ZooKeeper::PathCache - cache all immediate children of a parent node

# VERSION

version 0.0.1

# DESCRIPTION

ZooKeeper::PathCache is a facade over a ZooKeeper handle,
used for caching the contents of all immediate children nodes
of the specified path.

This works by including a version number in the path of child nodes,
so that one watcher can be set to monitor version changes in any child.

# ATTRIBUTES

## handle

## path

## serialize

## deserialize

# METHODS

## create

## delete

## set

## get

## get\_children

## exists

## sync

# AUTHOR

Mark Flickinger

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Mark Flickinger.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
