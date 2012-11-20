package Echo360;

use 5.014002;
use strict;
use warnings;

use Scalar::Util 'refaddr';
use LWP::UserAgent;
use HTML::Parser;
use Net::OAuth;
use XML::Simple;
use Data::Dumper;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Echo360 ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();
our $VERSION = '0.01';
use vars qw($AUTOLOAD);

my %uri_names = qw(term terms course courses terms terms courses courses);
my %_data;

sub new {
	my ($self, %args) = @_;
	my %cfg = map {uc $_ => $args{$_}} %args;
	$self = bless {}, $self;
	$_data{refaddr $self} = \%cfg;
	return $self;
}

sub AUTOLOAD {
	my $self = shift;
	(my $attr = $AUTOLOAD) =~ s/^.*:://;
	my ($action, $label)  = split '_', $attr;

	my $resp;
	if ($action eq 'add') {
		my %args = @_;
		my %xml_args = map {$_ => '<![CDATA['.$args{$_}.']]>'} keys %args;
		my $p = XML::Simple->new(NoAttr => 1, KeyAttr => {});
		my $xml = $p->XMLout(\%xml_args, RootName=>$label, NoEscape => 1);	
		$resp = $self->_send('POST', "/$uri_names{$label}", $xml);
	} elsif ($action eq 'get') {
		$resp = $self->_send('GET', "/$uri_names{$label}");
	} elsif ($action eq 'delete') {
		my $id = shift;
		$resp = $self->_send('DELETE', "/$uri_names{$label}/$id");	
	} elsif (my $val = shift) {
		$_data{refaddr $self}->{_data}{$attr} = $val;
	}

	if ($resp and $resp->code >= 400) {
		$_data{refaddr $self}->{_ERROR} = [parse_error($resp)]; 
		return 0;
	}

	($resp and $resp->content)  ? $self->_obj_builder($label, XML::Simple->new()->XMLin($resp->content)) : 1;
}

sub parse_error {
	my $resp = shift;
	my @errors;
	my $pre_found = 0;
	my $html_parser = HTML::Parser->new(
		start_h => [sub {
			for (@_) {$pre_found++ if $_ eq 'pre'}
		}, 'tag'],
		text_h => [sub {
			for (@_) { s/\n//; s/\s\s//g; push @errors, $_ if $pre_found;}
		}, 'text'],
		end_h => [sub {
			for (@_) {$pre_found = 0 if $_ eq '/pre'}
		}, 'tag']
	);
	my $content = $resp->content;
	$html_parser->parse($content);
	return @errors;
}	

sub errstr {
	my $self = shift;
	join ' : ', map {s/^\s+?\n+// or s/\s+?\n+$//; $_} @{$_data{refaddr $self}->{_ERROR}};
}

sub _send {
	my ($self, $method, $uri, $xml) = @_;
	my $timestamp = time();
	my $nonce = int rand 99999999;
	
	my $oauth_request = Net::OAuth->request('consumer')->new(
		consumer_key => $_data{refaddr $self}{'KEY'},
		consumer_secret => $_data{refaddr $self}{'SECRET'},
		request_url => $_data{refaddr $self}{'URL'}. $uri,
		request_method => uc $method,
		signature_method => "HMAC-SHA1",
		timestamp => $timestamp,
		nonce => $nonce,
		extra_params => {
			'xoauth_requestor_id' => $_data{refaddr $self}{'USERNAME'} . '@' . $_data{refaddr $self}{'KEY'},
		},
	);

	$oauth_request->sign;
	
	my $req = HTTP::Request->new(uc $method => $_data{refaddr $self}{'URL'}.$uri.'?xoauth_requestor_id='.$_data{refaddr $self}{'USERNAME'}.'@'.$_data{refaddr $self}{'KEY'});
	$req->header('Content-type' => 'application/xml');
	$req->header('Authorization' => $oauth_request->to_authorization_header);
	$req->content($xml) if $xml;

	my $ua = LWP::UserAgent->new;
	my $oauth_response = $ua->request($req);
	return $oauth_response;
}

sub DESTROY {
	my $self = shift;
	delete $_data{refaddr $self};
}


# Dynamic object related subs
sub _obj_builder {
	my ($self, $name, $xml) = @_;
	my $obj_name = 'Echo360::'.ucfirst($uri_names{$name});
	my $all_objs;	
	
	$name =~ s/s$//;
	my $attr_name = ($name eq 'term' or $name eq 'course') ? 'name' : '';

	for my $key (keys %{$xml->{$name}}) {
		my $obj = bless {}, $obj_name;
		no strict "refs";
		*{$obj_name."::AUTOLOAD"} = \&_obj_AUTOLOAD;
		
		$obj->$attr_name($key);
		for my $attr (keys %{$xml->{$name}{$key}}) {			
			$obj->$attr($xml->{$name}{$key}{$attr})
		}
		
		push @$all_objs, $obj;
	}
	return $all_objs;
}

sub _obj_AUTOLOAD {
	my $self = shift;
	(my $attr = $AUTOLOAD) =~ s/^.*:://;
	
	if (my $val = shift) {
		if (ref $val eq 'ARRAY') {
			push @{$_data{refaddr $self}{_data}{$attr}}, $_ for @$val;
		} else {
			$_data{refaddr $self}{_data}{$attr} = $val
		}
	} else {
		return $_data{refaddr $self}{_data}{$attr};
	}
}

sub exists {
	my ($self, $search_key, $search_val) = @_;
	
	for my $key (keys %_data) {
		my $obj = $_data{$key};
		next unless exists $_data{$key}->{_data};
		for (keys %{$_data{$key}->{_data}}) {
			return $obj if $_ eq $search_key and $_data{$key}->{_data}{$_} eq $search_val;
		}
	}
	return 0;
}



1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Echo360 - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Echo360;
  todo

=head1 DESCRIPTION

  todo
  
=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Kiel Stirling, E<lt>kiel@cpan.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Kiel Stirling

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
