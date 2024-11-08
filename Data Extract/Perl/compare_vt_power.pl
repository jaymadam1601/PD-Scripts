#!/usr/bin/perl

###############################################################################
# Script Name: Script to comapre multiple recipe of one block
# Author: Jay Madam (jjmadam18@gmail.com)
#
# Description:
# This Perl script is designed to compare various physical design metrics across
# multiple directories (referred to as "invs" directories). It extracts and
# compiles data on VT cell distribution, power consumption, and stage-wise 
# details from reports generated in a physical design workflow.
#
# Supported metrics include:
# - VT (Voltage Threshold) cell distribution
# - Power consumption before and after optimizations
# - Stage processing and directory validation
#
# Each metric can be output in tabular format and, optionally, CSV format.
# The stages processed are typically "place", "clock", and "route", but custom
# stages can also be specified using the -stage option.
#
# Usage:
#   perl script.pl -d <invs_directories> [optional arguments]
#
# Required Arguments:
# -d <invs_directories>
#       Comma-separated list of directories for invs to compare. These should
#       contain the relevant reports for each physical design stage.
#
# Optional Arguments:
# -stage <stage>
#       Specify the PNR stage to process, such as place, clock, or route.
#       Default is "all", which will include all configured stages.
#
# -vt
#       Print the VT cell distribution table.
#
# -power
#       Print the power consumption table (before and after optimizations).
#
# -col_width <int>
#       Set the column width for the table output. Default width is 30.
#
# -csv <file_name>
#       Output the results in CSV format to the specified file.
#
# -help, -h
#       Display this usage information.
#
# Environment Variables:
# - BLOCKPATH and MY_BLOCK
#       These environment variables are used to determine the working directory
#       for the script and locate the block design information.
#
# Features and Workflow:
# 1. Validates each provided directory, ensuring it exists and contains the
#    expected files for the specified stages.
# 2. Extracts the design name from a block configuration file.
# 3. Identifies available PNR stages in the specified directories and selects
#    only those that have valid logs.
# 4. For each selected stage, extracts VT and power metrics from compressed
#    report files, then prints or writes the results to a file.
# 5. Supports custom column widths and flexible stage selection.
#
# Important Notes:
# - Ensure all directories contain valid report files in gzip format.
# - VT data, power consumption before and after optimization, and other metrics
#   are only extracted if the corresponding files are available in the specified
#   directories.
#
# Example Command:
#   perl script.pl -d /path/to/invs1 /path/to/invs2 -stage place -vt -power -csv results.csv
#
# This command will compare the "place" stage across the directories `/path/to/invs1`
# and `/path/to/invs2`, printing VT and power data to the terminal, and also saving
# the results in `results.csv`.
#
###############################################################################


use POSIX;
use warnings;
use Getopt::Long;

my $divider_width = 30;
my $field_col_width = $divider_width - 2;

my @invs_dir; my $stage; my $csv_file; my $fh; 
my $col_width = 0;
my $print_timing = 0;
my $print_density = 0;
my $print_congestion = 0;
my $print_violation = 0;
my $print_vt = 0;

sub info {
    print <<"END_USAGE";
Usage: $0 <args>

Required:
    -d <invs_directories>
        Specify the invs directories to compare.

Optional:
    -stage <stage> (all/place/clock/route)
        Specify the stage to process. 
        Default: all (if stage log is created).

    -vt -power
        Specify the tables to print.
	Default: all tables will be printed.

    -col_width <int>
        Set the column width for the table.
        Default: 30.

    -csv <file_name>
        Output the data in CSV format.

END_USAGE
    exit;
}


GetOptions(
    'd=s{,}' => \@invs_dir, 
    'stage=s' => \$stage, 
    'vt' => \$print_vt,
    'power' => \$print_power,
    'help' => \&info, 
    'h' => \&info,
    'col_width=i' => \$col_width,
    'csv=s' => \$csv_file,
) or die "Invalid options passed\n";

if (!$col_width) {
	$col_width = 30;
}

foreach my $invs (@invs_dir) {
    if (!-d $invs) {
        die "Error: '$invs' is not a directory\n";
    }
}

if (!defined $stage) {
    $stage = "all";
}

my $BLOCKPATH = $ENV{'BLOCKPATH'}; chomp($BLOCKPATH);
my $BLOCK = $ENV{'MY_BLOCK'}; chomp($BLOCK);
my $BLOCK_ROOT = "${BLOCKPATH}/${BLOCK}"; chdir $BLOCK_ROOT;

my $design = `egrep "set DESIGN " scripts/con/block_config.tcl | awk '{print \$3}'`; chomp $design; print "$design\n";

my %define_stage = (place => "100_place", clock => "300_clock" , post_clock => "400_post_clock", route => "500_route" , route_opt => "600_route_opt");
my %define_stage_log = (place => "place", clock => "clock" , post_clock => "post_clock", route => "route" , route_opt => "route_opt");
my %p_stage = (place => "0", clock => "0", post_clock => "0", route => "0", route_opt => "0"); 
my @pnr_stages;

if ($stage eq "all" || $stage eq "") {

    foreach my $invs (@invs_dir) {
	$invs =~ s/\/$//;
        my $place_log = "${invs}/$define_stage{'place'}/logs/$define_stage_log{'place'}.log.gz";	
        my $clock_log = "${invs}/$define_stage{'clock'}/logs/$define_stage_log{'clock'}.log.gz";
	my $post_clock_log = "${invs}/$define_stage{'post_clock'}/logs/$define_stage_log{'post_clock'}.log.gz";
        my $route_log = "${invs}/$define_stage{'route'}/logs/$define_stage_log{'route'}.log.gz";
	my $route_opt_log = "${invs}/$define_stage{'route_opt'}/logs/$define_stage_log{'route_opt'}.log.gz";
        if (-e $place_log) {
            $p_stage{'place'}++;
            if (-e $clock_log) {
                $p_stage{'clock'}++;
		if (-e $post_clock_log) {
			$p_stage{'post_clock'}++;
			if (-e $route_log) {
				$p_stage{'route'}++;
				if (-e $route_opt_log) {
					$p_stage{'route_opt'}++;
				}
			}
		}
            }
        }
    }
} elsif (exists($define_stage{$stage})) {
    push @pnr_stages, $stage;
} else {
    print "ERROR :: Please enter valid pnr stage <place/clock/route/all> \n";
    exit;
}

foreach my $stage_name ('place', 'clock', 'post_clock', 'route', 'route_opt') {
    if ($p_stage{$stage_name} >= 1) {
        push @pnr_stages, $stage_name;
    }
}
print "@pnr_stages\n";

if (!$print_timing && !$print_density && !$print_congestion && !$print_violation && !$print_vt && !$print_power) {
    $print_timing = $print_density = $print_congestion = $print_violation = $print_vt = $print_power = 1;
}

if (defined $csv_file) {
    open($fh, '>', $csv_file) or die "Cannot open file '$csv_file' for writing: $!\n";
}




foreach my $pnr (@pnr_stages) {
	my @rpt_dirs;
	my @vt_rpts;
	my @before_power;
	my @after_power; 
	
	foreach my $invs (@invs_dir) {
		$invs =~ s/\/$//;
		my $rpt_dir_tmp = "${invs}/$define_stage{$pnr}/rpts";
		#print "$rpt_dir_tmp";
		if (-d $rpt_dir_tmp) {
			push @rpt_dirs, $rpt_dir_tmp;
			my $vt_rpt_tmp = `ls ${rpt_dir_tmp}/av_gate_count.rpt.gz 2>/dev/null`; chomp $vt_rpt_tmp;
			$vt_rpt_tmp = $vt_rpt_tmp ? $vt_rpt_tmp : "-";
			push @vt_rpts, $vt_rpt_tmp;
            		my $before_power_tmp =`ls ${rpt_dir_tmp}/Power_beforeOpt.rpt.gz 2>/dev/null`; chomp $before_power_tmp;
			$before_power_tmp = $before_power_tmp ? $before_power_tmp : "-"; 
			push @before_power, $before_power_tmp;
			
			my $after_power_tmp =`ls ${rpt_dir_tmp}/${design}*global.power.rpt.gz 2>/dev/null`; chomp $after_power_tmp;
			$after_power_tmp = $after_power_tmp ? $after_power_tmp : "-"; 
			push @after_power, $after_power_tmp;
		} else {
			$rpt_dir_tmp = "-";
			push @rpt_dirs, $rpt_dir_tmp;
		}
	}
	format wholeHeader =

+-----------------------------------------------------------------------------------------------------------------------------------------------------+
|                                       >>>>>>>>>>>>>>>>>>>>>    Stage @<<<<<<<<<< <<<<<<<<<<<<<<<<<<<<<                                              |
$pnr
+-----------------------------------------------------------------------------------------------------------------------------------------------------+
.

    $~ = wholeHeader;
    write;
	get_vt_table(@vt_rpts) if $print_vt;
	get_power_table("Total Power Before", @before_power) if $print_power;
	get_power_table("Total Power After", @after_power) if $print_power;
	if (defined $csv_file) {
		print $fh "Stage $define_stage{$pnr},,\n";
		get_vt_csv_table(@vt_rpts) if $print_vt;

		get_power_csv_table("Total Power Before", @before_power) if $print_power;
		get_power_csv_table("Total Power After", @after_power) if $print_power;
		print $fh "\n";
		
	}
	
}

sub timestamp_check {
    my ($file_1, $file_2) = @_;
    
    my $mtime_1 = (stat $file_1)[9];
    my $mtime_2 = (stat $file_2)[9];
    
    if (!defined $mtime_1 || !defined $mtime_2) {
        return 0;
    }

    return $mtime_1 < $mtime_2 ? 1 : 0;
}

sub get_vt_per {
    my $rpt = $_[0];
    my @vt_types = ('SVT8', 'LVT8', 'ULVT8', 'Instances', 'Flops', 'Total adjusted nand2 gates');
    my @vt_values;

    if (-e $rpt) {
        foreach my $vt (@vt_types) {
            my $value = `zcat $rpt | sed -e '1,/${design}:/ d' | grep '[[:blank:]]$vt ' | awk -F':' '{print \$(NF)}'`;
            chomp $value;
            push @vt_values, $value || "-";
        }
        return @vt_values;
    } else {
        return ("-", "-", "-", "-", "-", "-");
    }
}

sub get_power {
    my $rpt = $_[0];
    
    if (-e $rpt) {
	my $value = `zcat $rpt | grep "Total Power:" | awk '{print \$NF}'`;
	chomp $value;
	print $value
	return $value;
    } else {
	my $value = "-";
	return $value;
    }
}


sub get_vt_csv_table {
    my (@files) = @_;
    my @vt_values;
    my @dirs;

    my @header = ("VT Table (%)");

    foreach my $file (@files) {
        push @vt_values, [get_vt_per($file)];
        

        my @dir_split = split(/\//, $file);
        my $dir = (-e $file) ? $dir_split[-4] : "-";
        push @header, $dir;
    }

  
    print $fh join(",", @header) . "\n";

    my @all_vt = ('SVT8', 'LVT8', 'ULVT8', 'Instances', 'Flops', 'Total adjusted nand2 gates');


    for (my $i = 0; $i < @all_vt; $i++) {
        my @row = ($all_vt[$i]);
        foreach my $vt_ref (@vt_values) {
            push @row, $vt_ref->[$i];
        }
  
        print $fh join(",", @row) . "\n";
    }
} 

sub get_vt_table {
    my (@files) = @_;

    my @vt_values;
    my @dirs;

    my $divider = "+" . "-" x $divider_width . "+";
    my $header = sprintf("|  %-*s|", $field_col_width, "VT Table (%)");

    foreach my $file (@files) {
        $divider .= "-" x ($col_width+2) . "+";
        push @vt_values, [get_vt_per($file)];
        my @dir_split = split(/\//, $file);
		my $dir;
		if (-e $file) {
			$dir = $dir_split[-4];
		} else {
			$dir = "-";   
		}	
        if (length($dir) > $col_width ) {
            $dir = substr($dir, 0, $col_width - 1) . "...";
            $header .= sprintf("%-${col_width}s|", $dir);
        } else {
            $header .= sprintf("  %-${col_width}s|", $dir);
        } 
    }
    print "$divider\n$header\n$divider\n";
    my @all_vt = ('SVT8', 'LVT8', 'ULVT8', 'Instances', 'Flops', 'Total adjusted nand2 gates');

    for (my $i = 0; $i < @all_vt; $i++) {
        my $row = sprintf("|  %-*s|", $field_col_width, $all_vt[$i]);
        foreach my $vt_ref (@vt_values) {
            $row .= sprintf("  %-${col_width}s|", $vt_ref->[$i]);
        }
        print "$row\n";
    }
    print "$divider\n";
}

sub get_power_csv_table {
	my ($label, @files) = @_;
	my @data;
	push @data, $label;
	
	foreach my $file (@files) {
		my $tmp = get_power($file);
		push @data, $tmp;
	}
	print $fh join(",", @data) . "\n";
	
}

sub get_power_table {
	my ($label, @files) = @_;
    	my $divider = "+" . "-" x $divider_width . "+";

    	my $body = sprintf("|  %-*s|", $field_col_width, $label);
	foreach my $file (@files) {
		$divider .= "-" x ($col_width+2) . "+";
        	$body .= sprintf("  %-${col_width}s|", get_power($file));
	}
	print "$body\n$divider\n";
}
