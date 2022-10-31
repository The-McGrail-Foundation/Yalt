#!/usr/bin/perl

# Copyright 2021  Peregrine Computer Consultants Corporation
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

use strict;
use warnings;

use POE;
use POE::Wheel::FollowTail;
use Getopt::Std;
use MIME::Lite;

use FindBin;
use File::Spec;

BEGIN {
my @plugins = glob( File::Spec->catdir($FindBin::Bin, '..', 'lib') . '/Yalt/*' );
foreach my $plugin (@plugins) {
  eval {
    require $plugin;
  } or do {
    die("Error while loading module: $@");
  }
}
};

sub parse_input($$);

our $VERSION = 0.1;

my %opts;
our $mailfrom;
our $mailto;
our %checks;
my $pid;

our @services;

getopts('c:df:', \%opts);

if(not defined $opts{c}) {
  warn "A config file (-c parameter) is needed\n";
  exit;
} elsif (-f $opts{c}) {
  if($opts{c} !~ /^\//) {
    warn "Config file must be specified with an absolute path\n";
    exit;
  } else {
    do $opts{c};
    # Set additional default values
    foreach my $service ( @services ) {
      $checks{$service}{failures} = 0;
      $checks{$service}{first_notify} = 1;
    }
  }
} else {
  warn "Configuration file $opts{c} not found\n";
  exit;
}

if(not defined $opts{f}) {
  warn "Files to be checked (-f parameter) are needed\n";
  exit;
}

if(defined $opts{d}) {
  # Become a daemon: fork, detach, ...
  if ($pid = fork())  {
    exit 0;
  } elsif (defined($pid)) {
    setpgrp(0, 0);
    close(STDIN);
    close(STDOUT);
    close(STDERR);
    chdir("/tmp");
  } else {
    die "Can't fork: $!\n\n";
  }
}

my @files_to_tail = split(/,/, $opts{f});

foreach my $filename (@files_to_tail) {
  POE::Session->create(
    inline_states => {
      _start => sub {
        push @{$_[HEAP]{messages}}, POE::Wheel::FollowTail->new(
          Filename   => "$filename",
          InputEvent => "got_input",
        );
      },
      got_input => sub {
        parse_input($_[ARG0],\@services),
      },
    }
  );
}

sub parse_input($$) {
  my $line = shift;
  my $services = shift;
  my @services = @{$services};
  my $logerr;

  foreach my $service ( @services ) {
    if ((defined $checks{$service}{textko}) and ($line =~ /$checks{$service}{textko}/)) {
      push(@{$checks{$service}{errors}}, $line);
      if ($checks{$service}{first_notify}) {
        if($checks{$service}{failures} >= $checks{$service}{maxfailures}) {
          $logerr = join("\n", @{$checks{$service}{errors}});
          if (defined $checks{$service}{prev_line} and defined $checks{$service}{prev_lines} and ($checks{$service}{prev_lines} > 0)) {
            $logerr .= "\n\nPrevious log lines:\n";
            for (my $cnt = 0; $cnt <= $checks{$service}{prev_lines}; $cnt++) {
              my $logline = $checks{$service}{prev_line}[$cnt];
              $logerr .= $logline . "\n";
            }
          }
          $checks{$service}{action}(0, $checks{$service}, $logerr);
          undef $logerr;
          delete $checks{$service}{prev_line};
          $checks{$service}{first_notify} = 0;
          $checks{$service}{last_failure_notify} = time();
        }
      }
      $checks{$service}{last_error} = $line;
      $checks{$service}{failures}++;
      print $line . "\n";
    }
    if ((defined $checks{$service}{textok}) and ($line =~ /$checks{$service}{textok}/)) {
      if($checks{$service}{first_notify} eq 0) {
        $checks{$service}{action}(1, $checks{$service}, $logerr);
        $checks{$service}{last_error} = undef;
        $checks{$service}{failures} = 0;
        $checks{$service}{first_notify} = 1;
        $checks{$service}{last_failure_notify} = undef;
      }
    }
    if ((defined $checks{$service}{last_failure_notify}) and (time() - $checks{$service}{last_failure_notify}) > $checks{$service}{timelimit}) {
      if($checks{$service}{alert_once} eq 0) {
        $logerr = join("\n", @{$checks{$service}{errors}});
        $checks{$service}{action}(1, $checks{$service}, $logerr);
      }
      undef $logerr;
      delete $checks{$service}{prev_line};
      $checks{$service}{last_error} = undef;
      $checks{$service}{failures} = 0;
      $checks{$service}{first_notify} = 1;
      $checks{$service}{last_failure_notify} = undef;
      delete $checks{$service}{errors};
    }
    push(@{$checks{$service}{prev_line}}, $line);
  }
}

POE::Kernel->run();
exit;
