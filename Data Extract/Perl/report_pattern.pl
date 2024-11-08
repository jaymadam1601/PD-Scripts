#!/usr/bin/perl

######################################################################################################
# Script Name: report_pattern.pl
# Author: Jay Madam (jjmadam18@gmail.com)                                                          
#
# Description:
# This Perl script is used to analyze a timing report from Innovus (EDA Tool)
# It processes the report to gather timing information and organizes it into various categories, 
# such as beginpoints, endpoints, and slack times. The script can filter the report by specifying 
# different options (e.g., printing only beginpoints, only endpoints, or sorting by slack values).
# It is particularly useful for analyzing and optimizing timing in physical design workflows.
# 
#  Usage:
#   perl invs_compare.pl <timing_report> [options]
# 
# Required:
#   <timing_report>  : Specify the invs timing report file to process.
# 
# Optional:
#   -b               : Print only beginpoint patterns and their count.
#   -e               : Print only endpoint patterns and their count.
#   -w               : Print beginpoint and endpoint names without pattern matching.
#   -d               : Print endpoints first, followed by their multiple beginpoints.
#   -p <pattern>     : Specify a pattern to replace in beginpoints and endpoints 
#					   (default: '_1_' --> '_*_').
#   -h, --help       : Display this help message.
#
# How the script works:
# The script reads a gzipped timing report, extracts information about beginpoints, endpoints, 
# and their corresponding slack values. Depending on the options provided, the script can:
#   1. Print the count of beginpoints or endpoints.
#   2. Show slack times for each point.
#   3. Replace patterns in the beginpoint and endpoint names.
#   4. Print the multiple beginpoint violated by same endpoint.
#   5. Print data with slack times in a sorted manner.
#
# The script outputs the results based on user-defined filters, either in a simple count format 
# or with detailed slack information.
###############################################################################


use POSIX;
use strict;
use warnings;
use Getopt::Long;

my $only_beginpoint = 0; my $only_endpoint = 0; my $endpoint_dominated = 0; my $replace_pattern;
my $without_pattern = 0; my $replace_pattern_set = 0;

GetOptions(
    'b' => \$only_beginpoint, 
    'h|help'  => \&info,
    'e' => \$only_endpoint,
    'd' => \$endpoint_dominated,
    'p=s' => sub { $replace_pattern = $_[1]; $replace_pattern_set = 1; },
	'w' => \$without_pattern
) or die("Error in command line arguments\n");

$replace_pattern = '_*_' unless defined $replace_pattern;

if ($only_beginpoint && $only_endpoint) {
    die "Error: Cannot specify both -b (only beginpoint) and -e (only endpoint).\n";
}

if ($without_pattern && $replace_pattern_set) {
	die "Error: Cannot specify both -p and -w. \n";
}

sub info {
    print <<"END_USAGE";
Usage: $0 <args>

Required:
     <invs_timing_report>
        Specify the invs timing report.

Optional:
    -b (Specify to print only beginpoint Patterns and their count)
    -e (Specify to print only endpoint Patterns and their count)
	-w (Specify to print beginpoint and endpoint name without pattern)
    -d (To print endpoints first and their multiple beginpoint)
        Example:
        Endpoint: endpoint_*_*/d -> Count: 2
            Beginpoint: beginpoint_*_*/q -> Count: 1
            Beginpoint: beginpoint_*_/q -> Count: 1
    -p (Specify pattern to be replaced with number {default: _1_ --> _*_} )
        Note: Please specify pattern in between "_"
        Example: -> _pattern_
END_USAGE
    exit;
}

if (@ARGV == 0) {
    print "Error: Timing report file not specified.\n";
    info();
}

my $timing_rpt = $ARGV[0];

# Initialize hash structures for storing data
my (%all_beginpoint, %all_beginpoint_pattern);
my (%all_endpoint, %all_endpoint_pattern);
my (%all_point, %all_point_pattern);
my (%all_point_end, %all_point_end_pattern);
my (%all_slack, %all_slack_pattern);
my (%all_slack_end, %all_slack_end_pattern);
my (%all_beginpoint_slack, %all_beginpoint_slack_pattern);
my (%all_endpoint_slack, %all_endpoint_slack_pattern);

open(my $fp_timing_rpt, '-|', "zcat $timing_rpt") or die "Could not open file $timing_rpt : $!";    

my $beginpoint; 
my $endpoint;

while (my $line = <$fp_timing_rpt>) {
    chomp($line);
    if ($line =~ /Beginpoint:/) {
        my @fields = split(/\s+/, $line);
        $beginpoint = $fields[1];
    }
    if ($line =~ /Endpoint:/) {
        my @fields = split(/\s+/, $line);
        $endpoint = $fields[1];
    }
    if ($line =~ /Slack Time/) {
        my @fields = split(/\s+/, $line);
        my $slack = $fields[3];
        if ($slack =~ /^-\d+\.\d+$/) {
            
			if ($without_pattern) {
				$all_beginpoint{$beginpoint}++;
				$all_endpoint{$endpoint}++;
				push @{$all_beginpoint_slack{$beginpoint}}, "$slack";
				push @{$all_endpoint_slack{$endpoint}}, "$slack";
				if ($endpoint_dominated) {
					$all_point_end{$endpoint}{$beginpoint}++;
					push @{$all_slack_end{$endpoint}{$beginpoint}}, "$slack";
				} else {
					$all_point{$beginpoint}{$endpoint}++;
					push @{$all_slack{$beginpoint}{$endpoint}}, "$slack";
				}
			} else {
				$beginpoint =~ s/_(\d+)_/$replace_pattern/g;
				$endpoint =~ s/_(\d+)_/$replace_pattern/g;
				$all_beginpoint_pattern{$beginpoint}++;
				$all_endpoint_pattern{$endpoint}++;
				push @{$all_beginpoint_slack_pattern{$beginpoint}}, "$slack";
				push @{$all_endpoint_slack_pattern{$endpoint}}, "$slack";
				if ($endpoint_dominated) {
					$all_point_end_pattern{$endpoint}{$beginpoint}++;
					push @{$all_slack_end_pattern{$endpoint}{$beginpoint}}, "$slack";
				} else {
					$all_point_pattern{$beginpoint}{$endpoint}++;
					push @{$all_slack_pattern{$beginpoint}{$endpoint}}, "$slack";
				}
			}
            undef $beginpoint;
            undef $endpoint;
        }
    }
}
close($fp_timing_rpt);

if ($without_pattern) {
	my @sorted_beginpoints = sort { $all_beginpoint{$b} <=> $all_beginpoint{$a} } keys %all_beginpoint;
	my @sorted_endpoints = sort { $all_endpoint{$b} <=> $all_endpoint{$a} } keys %all_endpoint;
	
	if ($endpoint_dominated || $only_endpoint) {
		foreach my $one_endpoint (@sorted_endpoints) {
			my ($min_end, $max_end) = get_min_max(@{ $all_endpoint_slack{$one_endpoint} });
			if ($only_endpoint) {
				print "Endpoint: $one_endpoint -> Count: $all_endpoint{$one_endpoint} -> Slack:(min:$min_end max:$max_end)";
			} else {
				print "Endpoint: $one_endpoint -> Count: $all_endpoint{$one_endpoint} -> Slack:(min:$min_end max:$max_end)\n";
				foreach my $one_beginpoint (keys %{ $all_point_end{$one_endpoint} } ) {
					my ($min, $max) = get_min_max(@{ $all_point_end{$one_endpoint}{$one_beginpoint} });
					print "  Beginpoint: $one_endpoint -> Count: $all_point_end{$one_endpoint}{$one_beginpoint} -> Slack:(min:$min max:$max) \n";
				}
			}
			print "\n";
		}
	} else {
		foreach my $one_beginpoint (@sorted_beginpoints) {
			my ($min_begin, $max_begin) = get_min_max(@{ $all_beginpoint_slack{$one_beginpoint} });
			if ($only_beginpoint) {
				print "Beginpoint: $one_beginpoint -> Count: $all_beginpoint{$one_beginpoint} -> Slack:(min:$min_begin max:$max_begin)";
			} else {
				print "Beginpoint: $one_beginpoint -> Count: $all_beginpoint{$one_beginpoint} -> Slack:(min:$min_begin max:$max_begin)\n";
				foreach my $one_endpoint (keys %{ $all_point{$one_beginpoint} } ) {
					my ($min, $max) = get_min_max(@{ $all_point{$one_beginpoint}{$one_endpoint} });
					print "  Endpoint: $one_endpoint -> Count: $all_point{$one_beginpoint}{$one_endpoint} -> Slack:(min:$min max:$max)\n";
				}
			}
		} 
	}
} else {
	my @sorted_beginpoints_pattern = sort { $all_beginpoint_pattern{$b} <=> $all_beginpoint_pattern{$a} } keys %all_beginpoint_pattern;
	my @sorted_endpoints_pattern = sort { $all_endpoint_pattern{$b} <=> $all_endpoint_pattern{$a} } keys %all_endpoint_pattern;
	
	if ($endpoint_dominated || $only_endpoint) {
		foreach my $one_endpoint_pattern (@sorted_endpoints_pattern) {
			my ($min_end, $max_end) = get_min_max(@{ $all_endpoint_slack_pattern{$one_endpoint_pattern} });
			if ($only_endpoint) {
				print "Endpoint: $one_endpoint_pattern -> Count: $all_endpoint_pattern{$one_endpoint_pattern} -> Slack:(min:$min_end max:$max_end)";
			} else {
				print "Endpoint: $one_endpoint_pattern -> Count: $all_endpoint_pattern{$one_endpoint_pattern} -> Slack:(min:$min_end max:$max_end)\n";
				foreach my $one_beginpoint_pattern (keys %{ $all_point_end_pattern{$one_endpoint_pattern} }) {
					my ($min, $max) = get_min_max(@{ $all_slack_end_pattern{$one_endpoint_pattern}{$one_beginpoint_pattern} });
					print "  Beginpoint: $one_beginpoint_pattern -> Count: $all_point_end_pattern{$one_endpoint_pattern}{$one_beginpoint_pattern} -> Slack:(min:$min max:$max) \n";
				}
			}
			print "\n";
		}
	} else {
		foreach my $one_beginpoint_pattern (@sorted_beginpoints_pattern) {
			my ($min_begin, $max_begin) = get_min_max(@{ $all_beginpoint_slack_pattern{$one_beginpoint_pattern} });
			if ($only_beginpoint) {
				print "Beginpoint: $one_beginpoint_pattern -> Count: $all_beginpoint_pattern{$one_beginpoint_pattern} -> Slack:(min:$min_begin max:$max_begin)";
			} else {
				print "Beginpoint: $one_beginpoint_pattern -> Count: $all_beginpoint_pattern{$one_beginpoint_pattern} -> Slack:(min:$min_begin max:$max_begin)\n";
				foreach my $one_endpoint_pattern (keys %{ $all_point_pattern{$one_beginpoint_pattern} }) {
					my ($min, $max) = get_min_max(@{ $all_slack_pattern{$one_beginpoint_pattern}{$one_endpoint_pattern} });
					print "  Endpoint: $one_endpoint_pattern -> Count: $all_point_pattern{$one_beginpoint_pattern}{$one_endpoint_pattern} -> Slack:(min:$min max:$max)\n";
				}
			}
			print "\n";
		}
	}
}

sub get_min_max {
    my @numbers = @_;
    return unless @numbers;
    my @sorted_numbers = sort { $a <=> $b } @numbers;
    my $min = $sorted_numbers[0];
    my $max = $sorted_numbers[-1];
    return ($min, $max);
}
