#!/usr/bin/perl -w
#
# nagios: -epn
#
# Script created for event based servicenow tickets.
# #
# DESCRIPTION:
#	Perl written Nagios Alerts to send ticket information to a ServiceNow instance.  This will be fired
#	on a event handler.
#
#  OUTPUT:
#    upon successful completion, the script will return the
#    new incident id with TICKETID: prefix. no output is 
#    produced when updating an existing incident. if any error 
#    is encountered, the script will provide diagnostic details
#    with ERROR: prefix
#
# http://search.cpan.org/~mcrawfor/REST-Client/lib/REST/Client.pm
# Example install using cpanm:
#   sudo cpanm -i REST::Client
##

use strict;
use warnings;
use POSIX       qw( strftime );
use Time::Local qw( timegm );
use Cwd 'abs_path';
use File::Basename;
use MIME::Base64;
use REST::Client;
use JSON;
use Config::Properties;
use Log::Log4perl;

## Declare Logging
# Initialize Logger
my $log_conf = abs_path(dirname($0)) . "/log4perl.conf";
Log::Log4perl::init($log_conf);
my $logger = Log::Log4perl->get_logger();

## Variable declaration
my ($hostname,$hostip,$commandname,$currentstate,$timeinstate, $hostoutput) = @ARGV;
my $usr;
my $pwd;
my $path = abs_path(dirname($0)) . "/snNagios.properties";
my $update_state = ($currentstate eq "OK") ? 9 : 2;  #determine state based on current state
my $sysid;

$logger->info("$hostname,$hostip,$commandname,$currentstate,$timeinstate, $hostoutput");

## Hash Map Delcartions replace - to replace values in the config file
## fields = Created based on POST or PUT
my %replace = (
  "<hostname>" => $hostname,
  "<hostip>" => $hostip,
  "<commandname>" => $commandname,
  "<currentstate>" => $currentstate,
  "<timeinstate>" => $timeinstate,
  "<hostoutput>" => $hostoutput,
  "<update_state>" => $update_state,
);

my %fields;

## Load config File and set host endpoint and REST client

open my $cfg, '<', $path or die "unable to open file";

my $properties = Config::Properties->new();
$properties->load($cfg);
my $endpoint = $properties->getProperty('service.endpoint');

my $client = REST::Client->new(host => $endpoint);

## End of Variable declaration


## Main Methods Calls

find_CI(); ## find the Configuration Item

$sysid = find_existing_incident();  ## find existing incident sysid and add it to replace hash
$replace{"<sysid>"} = $sysid;

## If no incident is found and update_state is 9 (Resolved)
## then log error and exit.
## Otherwise, make the rest call
if (!length($sysid) && $update_state == '9'){
	$logger->error("No Incident Found but Host $hostanme went into an OK state");
}
else{
	rest_call();
}
close $cfg;

## BEGIN OF SUB ROUTINE's

sub getEncodedCredentials {
	return encode_base64($properties->getProperty("service.username") . ":". $properties->getProperty("service.password"), '');
}

sub getEndPoint {
	return $properties->getProperty('service.endpoint');
}

sub getCIEndPoint {
	return $properties->getProperty('service.ci_endpoint');
}

## Search and replace properties string with replace hash values
sub ReplaceParameters {
    my $s = shift;
    my $regex = join "|", keys %replace;
    $regex = qr/$regex/;
    
	$s =~ s/($regex)/$replace{$1}/g;
	$s =~ s/\\n/\n/g;

    return $s;
}

## Build fields hash based on operation (PUT/POST)
## Searchs properties with the key servicenow.PUT/POST
## then add to fields hash
sub buildFields {
	my $operation = shift;
	foreach my $props (keys %{$properties->getProperties()})
	{
		if ($props =~ /^servicenow.${operation}.(.*)/i) {
			my $propsValue = ReplaceParameters($properties->getProperty($props));
			my $propsName = $1;
			$propsName =~ s/^servicenow.${operation}.//g;
			$fields{$propsName} = $propsValue;
		}
	}
}

## Make Rest Call depending on sysid exist
## If sysid exist then PUT update incident
## If no sysid exist then POST create a new incident
sub rest_call {
	if (length($sysid)){
		$logger->info("Updating Incident $sysid");
		buildFields('PUT');
		$client->PUT(ReplaceParameters($properties->getProperty("service.uri.put.incident")),
			encode_json(\%fields),
			{'Authorization' => "Basic " . getEncodedCredentials(),
		 	'Content-Type' => 'application/json',
		 	'Accept' => 'application/json'});

	}else {
		$logger->info("Creating new Incident");
		buildFields('POST');
		$client->POST($properties->getProperty("service.uri.post.incident"),
			encode_json(\%fields),
			{'Authorization' => "Basic " . getEncodedCredentials(),
		 	'Content-Type' => 'application/json',
		 	'Accept' => 'application/json'});
	}
	my $decoded = decode_json($client->responseContent());
	
	if ($client->responseCode() == '200' || $client->responseCode() == '201') {
		$logger->info("Successful Incident Created/Updated");
		return;
	} else {
		$logger->error("Something went horribly wrong. ResponseCode: " . $client->responseCode());
		return;
	}
}

#  Find if the Host is an existing Configuration Item, if so return the name
sub find_CI {
	$logger->info("Staring Configuration Item query");

	$client->GET(ReplaceParameters($properties->getProperty("service.uri.get.cmdb_ci")),
            {'Authorization' => "Basic ". getEncodedCredentials(),
             'Accept' => 'application/json'});
	my $decoded = decode_json($client->responseContent());
	if ($client->responseCode() == '200' || $client->responseCode() == '201') {
		$logger->info("CI FOUND $hostname $hostip");
		$replace{"<ci_name>"} = $hostname;
		$replace{"<ci_location>"} = $decoded->{result}->[0]->{location}->{value};
	} elsif ($client->responseCode() == '404' || $client->responseCode() == '204') {
		$logger->info("NO CI FOUND $hostname $hostip");
		$replace{"<ci_name>"} = '';
		$replace{"<ci_location>"} = '';
	} else {
		$logger->error("Something went horribly wrong. ResponseCode: " . $client->responseCode());
	}
}

## Returns the sys_id of matching incident if it is active, matches the short_description, and created in the last 24 hours
sub find_existing_incident {
	my ($date,$time) = split / /, todayDateTime();

	$replace{"<date>"} = $date;
	$replace{"<time>"} = $time;

	my $client = REST::Client->new(host => getEndPoint());
	$client->GET(ReplaceParameters($properties->getProperty("service.uri.get.incident")),
		{'Authorization' => "Basic ". getEncodedCredentials(),
             'Accept' => 'application/json'});

	my $decoded = decode_json($client->responseContent());
	if ($client->responseCode() == '200' || $client->responseCode() == '201') {
		$logger->info("Incident Found.  responseCode: " . $client->responseCode() . 
			" Sysid: " . $decoded->{result}->[0]->{sys_id});
		return $decoded->{result}->[0]->{sys_id};
	} elsif ($client->responseCode() == '404' || $client->responseCode() == '204') {
		$logger->info("Incident Not Found.  responseCode: " . $client->responseCode());
		return '';
	} else {
		$logger->error("Something went horribly wrong. ResponseCode: " . $client->responseCode());
		return '';
	}
}

sub todayDateTime {
  my ($sec,$min,$hour,$d,$m,$y) = localtime();
  ($d,$m,$y) = (gmtime(timegm(0,0,0,$d,$m,$y) - 24*60*60))[3,4,5];
  return strftime("%Y-%m-%d %H:%M:%S", $sec,$min,$hour,$d,$m,$y);
}
