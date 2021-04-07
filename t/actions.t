#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib'; use lib 't';

use Test::More;

plan tests => 2;

use Yalt::Actions;

my %service;
$service{SERVICE}{description} = 'test';
$service{SERVICE}{timelimit} = 60;

is(Yalt::Actions::init(0, $service{"SERVICE"}, "log line"), "A problem in service test has been detected:\n\nlog line" );

like(Yalt::Actions::init(1, $service{"SERVICE"}, "log line"), qr/test service is working correctly or timeout 60 exceeded/, "Yalt::Actions::init" );
