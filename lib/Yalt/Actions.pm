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

package Yalt::Actions;

use MIME::Lite;

use Yalt::Sys;

sub init($$$) {
  my $status = shift;
  my $service = shift;
  my %service = %{$service};
  my $error = shift;
  my ($mailfrom, $mailto, $mailcc);

  my $server = Yalt::Sys::get_myhostname;
  my $subject;
  my @params;
  my $data;

  if($status eq 0) {
    if(ref $service{subject_ko_params} eq 'CODE') {
      $params[0] = $service{subject_ko_params}();
    } elsif(ref $service{subject_ko_params} eq 'ARRAY') {
      foreach my $srvparm ( @{$service{subject_ko_params}} ) {
        if(ref $srvparm eq 'CODE') {
          push(@params, &$srvparm($error));
        } else {
          push(@params, $srvparm);
        }
      }
    } else {
      $params[0] = $service{subject_ko_params};
    }

    if(defined $service{subject_ko}) {
      $subject = sprintf($service{subject_ko}, @params);
    } else {
      $subject = "Problem detected in service " . uc($service{description}) . " on host " . $server;
    }
    $data = "A problem in service $service{description} has been detected:\n\n" . $error;
  } elsif($status eq 1) {
    if(ref $service{subject_ok_params} eq 'CODE') {
      $params[0] = $service{subject_ok_params}();
    } elsif(ref $service{subject_ok_params} eq 'ARRAY') {
      foreach my $srvparm ( @{$service{subject_ok_params}} ) {
        if(ref $srvparm eq 'CODE') {
          push(@params, &$srvparm($error));
        } else {
          push(@params, $srvparm);
        }
      }
    } else {
      $params[0] = $service{subject_ok_params};
    }

    if(defined $service{subject_ok}) {
      $subject = sprintf($service{subject_ok}, @params);
    } else {
      $subject = "Problem detected in service " . uc($service{description}) . " on host " . $server;
    }
    $data = "$service{description} service is working correctly or timeout $service{timelimit} exceeded.\n\nService had $service{failures} errors in $service{timelimit} seconds.\n\nErrors were:\n\n $error";
  } else {
    # Status must be 0 (KO) or 1 (OK)
    return undef;
  }
  return ($subject, $data);
}

sub email($$$) {
  my $status = shift;
  my $service = shift;
  my %service = %{$service};
  my $error = shift;
  my ($mailfrom, $mailto, $mailcc);

  my $subject;
  my $data;

  ($subject, $data) = init($status, $service, $error);

  if(defined $service{from} and defined $service{to}) {
    $mailfrom = $service{from};
    $mailto = $service{to};
  } else {
    # Email must have a From and a To
    return undef;
  }

  if(defined $service{email_cc}) {
    if($service{email_cc} =~ /\@/) {
      $mailcc = $service{email_cc};
    } else {
      $mailcc = $service{email_cc}($error);
    }
  }

  my $tpl = "template/email.tpl";
  my $content;
  my $html = 0;
  if(-f $tpl) {
    open(my $fh, '<', $tpl) or die "cannot open file $tpl";
    {
        binmode($fh, ":encoding(UTF-8)");
        local $/;
        $content = <$fh>;
    }
    close($fh);
    $data =~ s/\n/<BR>/g;
    $content =~ s/%SUBJECT%/$subject/g;
    $content =~ s/%DATA%/$data/g;
    $html = 1;
  } else {
    $content = $data;
  }
  my $msg;
  if($html eq 1) {
    $msg = MIME::Lite->new(
                     From     => $mailfrom,
                     To       => $mailto,
                     Cc       => $mailcc,
                     Subject  => $subject,
                     Disposition => 'inline',
                     Type    =>'multipart/related'
                     );
    $part = MIME::Lite->new(
       Type     => 'text/html',
       Data     => $content,
    );
    $part->attr('content-type.charset' => 'UTF-8');
    $msg->attach($part);
    if(-f "$tpl.png") {
      my $img_id = (split(/\//, $tpl))[1];
      $msg->attach(
        Type => 'image/png',
        Id   => "$img_id.png",
        Path => "$tpl.png",
      );
    }
  } else {
    $msg = MIME::Lite->new(
                    From     => $mailfrom,
                    To       => $mailto,
                    Cc       => $mailcc,
                    Subject  => $subject,
                    Data     => $content,
                    );
  }
  $msg->send;
}

1;
