package Net::SMS::160By2;

no warnings;
use strict;
use Data::Dumper;
# Load this to handle exceptions nicely
use Carp;

# Load this to make HTTP Requests
use WWW::Mechanize;
use HTML::TagParser;
use URI;

# Load this to uncompress the gzip content of http response.
use Compress::Zlib;

=head1 NAME

Net::SMS::160By2 - Send SMS using your 160By2 account!

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

our $HOME_URL       = 'http://160by2.com/Login';
our $SENDSMS_URL     = 'http://160by2.com/FebSendSMS';
our $SENDSMS_SUBMIT_URL     = 'http://160by2.com/Feb7SendSMS';

=head1 SYNOPSIS

This module provides a wrapper around 160By2.com to send an SMS to any mobile number in 

India, Kuwait, UAE, Saudi, Singapore, Philippines & Malaysia at present.

you can use this as follows.

    use Net::SMS::160By2;

    my $obj = Net::SMS::160By2->new($username, $password);
    
    $obj->send_sms($msg, $to);

    # send additional params will print WWW::Mechanize detailed request and
    # responses

    my $debug_obj = Net::SMS::160By2->new($username, $password, {debug => 1});

    $debug_obj->send_sms($msg, $to);
    
Thats it!
    
=head1 SUBROUTINES/METHODS

=head2 new

This is constructor method.

input: username, password

A new object will be created with username, password attributes.

You can send additional params in a hash ref as 3rd parameter.

at present only debug option is handled in additional params.

output: Net::SMS::160By2 object

=cut

sub new {
	my $class = shift;
	
	# read username and password
	my $username = shift;
	my $password = shift;
	my $extra = shift;
	$extra = {} unless ref($extra) eq 'HASH';

	# Throw error in case of no username or password
	croak("No username provided") unless ($username);
	croak("No password provided") unless ($password);
	
	# return blessed object
	my $self = bless {
		'username' => $username,
		'password' => $password,
		'mobile'   => undef,
		'message'  => undef,
		'query_form' => undef,
		%{$extra}
	}, $class;
	return $self;
}

=head2 send_sms

This method is used to send an SMS to any mobile number.
input : message, to

where message contains the information you want to send.
      to is the recipient mobile number
      
=cut

sub send_sms {
	my ($self, $msg, $to) = @_;
	croak("Message or mobile number are missing") unless ($msg || $to);
	
	# trim spaces
	$msg =~ s/^\s+|\s+$//;
	$to =~ s/^\s+|\s+$//;

	# set message and mobile number
	$self->{message} = $msg;
	$self->{mobile} = $to;

	# create mechanize object
	my $mech = WWW::Mechanize->new(autocheck => 1);
	if ($self->{debug}) {
		$mech->add_handler("request_send", sub { shift->dump; return });
		$mech->add_handler("response_done", sub { shift->dump; return });
	}
	$mech->agent_alias( 'Windows Mozilla' );
	
	# Now connect to 160By2 Website login page
	$mech->get($HOME_URL);
	
	# handle gzip content
	my $response = $mech->response->content;
	if ( $mech->response->header('Content-Encoding') eq 'gzip' ) {
		$response = Compress::Zlib::memGunzip($response );
		$mech->update_html( $response ) 
	}

	# login to 160By2
	my $status = $self->_login($mech);
	
	die "Login Failed" unless $status;

	# sendsms from 160by2
	return $self->_send($mech);
}

sub _login {
	my ($self, $mech) = @_;

	# Get login form with htxt_UserName, txt_Passwd
	$mech->form_with_fields('username', 'password');
	
	# set htxt_UserName, txt_Passwd
	$mech->field('username', $self->{username});
	$mech->field('password', $self->{password});
	
	# submit form
	$mech->submit_form();
	
	# Verify login success/failed
	# handle gzip content
	my $response = $mech->response->content;
	if ( $mech->response->header('Content-Encoding') eq 'gzip' ) {
		$response = Compress::Zlib::memGunzip( $response );
		$mech->update_html( $response ) 
	}
	my $home_uri = URI->new($mech->base());
	my @q = $home_uri->query_form;
	$self->{query_form} = \@q;
	return $mech;
}

sub _send {
	my ($self, $mech) = @_;
	
	# Try to go to Home Page
	my $sendsms_uri = URI->new($SENDSMS_URL);
	$sendsms_uri->query_form(@{$self->{query_form}});

	my $sendsms_submit_uri = URI->new($SENDSMS_SUBMIT_URL);
	$sendsms_submit_uri->query_form(@{$self->{query_form}});
	
	# Get content of SendSMS form page
	$mech->get($sendsms_uri->as_string);

	my $response;
	if ( $mech->response->header('Content-Encoding') eq 'gzip' ) {
		# handle gzip content
		$response = $mech->response->content;
		$response = Compress::Zlib::memGunzip( $response );
		$mech->update_html( $response );
	}	    
	# set form action
	my $form = $mech->form_name('frm_sendsms');
	$form->action($sendsms_submit_uri);	
	
	# Use TagParser here, this will make our job easier
	my $tp = HTML::TagParser->new($response);
	my $sm_form = $tp->getElementById( "frm_sendsms" );
	my $sm_form_tree = $sm_form->subTree();
	
	# User HTML::TagParser to recognize dynamically generated mobile number input, message textarea element id/names
	my ($mob_elem) = $sm_form_tree->getElementsByAttribute('tabindex', "1");
	if ($mob_elem) { # we have to consider tabindex=1 as mobile number input
		$mech->field($mob_elem->getAttribute('id'), $self->{mobile});
	}
	my ($msg_elem) = $sm_form_tree->getElementsByAttribute('tabindex', "2");
	if ($msg_elem) { # we have to consider tabindex=2 as message textarea
		$mech->field($msg_elem->getAttribute('id'), $self->{message});
	}
	
	# set additional params
	my %params = @{$self->{query_form}};
    $mech->field('hid_exists', "no");
    $mech->field('feb2by2session', $params{id});
	# submit form
	$mech->submit();

	
	# is URL call Success?
	if ($mech->success()) {
	
		# Check sms sent successfully
		my $response = $mech->response->content;
		if($mech->response->header("Content-Encoding") eq "gzip") {
			$response = Compress::Zlib::memGunzip($response) ;
		}
		# return 1(true) in case of success
		return 1 if($response =~ m/Your message has been Sent/sig);
	}
	# return undef as failure
	return;
}

=head1 AUTHOR

Mohan Prasad Gutta, C<< <mohanprasadgutta at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-sms-160by2 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-SMS-160By2>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::SMS::160By2


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-SMS-160By2>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-SMS-160By2>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-SMS-160By2>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-SMS-160By2/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Mohan Prasad Gutta.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Net::SMS::160By2
