#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib'; use lib 't';

use Test::More;

plan tests => 1;

use Yalt::Sys;
use Sys::Hostname;

is(Yalt::Sys::get_hostname, hostname);
