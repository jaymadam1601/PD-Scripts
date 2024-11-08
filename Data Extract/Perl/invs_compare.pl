#!/usr/bin/perl

##############################################################################
# Script Name: invs_compare.pl
# Author: Jay Madam (jjmadma18@gmail.com)
#
# Description:
# This Perl script is designed to compare physical design metrics across
# multiple (n numbers of directories there is no limit) invs directories for a block. 
# It extracts and compiles data from reports on various design metrics, including
# timing, density, congestion, and violation counts, for different stages in the physical design flow.
#
# Supported Metrics:
# - Timing analysis (WNS, TNS, VP)
# - Density and congestion details
# - DRC violations and their count
# - Hold violations across different stages (place, clock, route)
#
# Usage:
#   perl invs_compare.pl -invs <invs_directories> [optional arguments]
#
# Required Arguments:
# -invs <invs_directories>
#       Comma-separated list of directories containing invs reports to be compared.
#       The directories must contain the necessary files for each stage.
#
# Optional Arguments:
# -stage <stage>
#       Specify the stage to process (place, clock, route). Default is "all" to process
#       all stages if not specified.
#
# -vt
#       Print the Voltage Threshold (VT) cell distribution table.
#
# -power
#       Print the power consumption table before and after optimizations.
#
# -density
#       Print the density analysis table for each directory.
#
# -congestion
#       Print the congestion analysis table for each directory.
#
# -drclog
#       Print DRC violation counts from the reports.
#
# -csv <file_name>
#       Output the results in CSV format to the specified file.
#
# -col_width <int>
#       Set the column width for table output. Default is 30.
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
# 1. Validates each provided directory, checking for required report files.
# 2. Extracts and compares timing (WNS, TNS, VP), density, congestion, and violation data.
# 3. Supports flexible column widths, customizable stage selection, and CSV export.
# 4. Outputs results in both tabular and CSV formats for easy analysis.
#
# Important Notes:
# - Ensure all directories contain valid report files for each required stage.
# - The script will handle missing files by substituting "-" in their place.
#
# Example Command:
#   perl invs_compare.pl -invs /path/to/invs1 /path/to/invs2 /path/to/invs3 -stage place -vt -power -csv results.csv
#
# This command will compare the "place" stage across the directories `/path/to/invs1`
# and `/path/to/invs2`, printing VT and power data to the terminal and also saving
# the results in `results.csv`.
#
###############################################################################


use POSIX;
use warnings;
use Getopt::Long;

my $divider_width = 26;
my $field_col_width = $divider_width - 2;

my @invs_dir; my $stage; my $csv_file; my $fh; 
my $invs_timing_summary = 0;
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
    -invs <invs_directories>
        Specify the invs directories to compare.

Optional:
    -stage <stage> (all/place/clock/route)
        Specify the stage to process. 
        Default: all (if stage log is created).

    -timing -density -congestion -violation -vt
        Specify the tables to print.
	Default: all tables will be printed.

    -col_width <int>
        Set the column width for the table.
        Default: 30.

    -csv_file <file_name>
        Output the data in CSV format.

    -invs_timing_summary
        Extract timing, denisty and congestion data from invs_timing_summary instead of timing_0* directories.

END_USAGE
    exit;
}


GetOptions(
    'invs=s{,}' => \@invs_dir, 
    'stage=s' => \$stage, 
    'timing' => \$print_timing,
    'density' => \$print_density,
    'congestion' => \$print_congestion,
    'violation' => \$print_violation,
    'vt' => \$print_vt,
    'help' => \&info, 
    'h' => \&info,
    'col_width=i' => \$col_width,
    'csv_file=s' => \$csv_file,
    'invs_timing_summary' => \$invs_timing_summary
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

my %define_stage = (place => "100_place", clock => "400_post_clock", route => "600_route_opt");
my %define_stage_log = (place => "place", clock => "post_clock", route => "route_opt");
my %p_stage = (place => "0", clock => "0", route => "0"); 
my @pnr_stages;

if ($stage eq "all" || $stage eq "") {

    foreach my $invs (@invs_dir) {
	$invs =~ s/\/$//;
        my $place_log = "${invs}/$define_stage{'place'}/logs/$define_stage_log{'place'}.log.gz";
        my $clock_log = "${invs}/$define_stage{'clock'}/logs/$define_stage_log{'clock'}.log.gz";
        my $route_log = "${invs}/$define_stage{'route'}/logs/$define_stage_log{'route'}.log.gz";
        my $cond_1 = timestamp_check($place_log, $clock_log);
        my $cond_2 = timestamp_check($clock_log, $route_log);
        if (-e $place_log) {
            $p_stage{'place'}++; 
            if (-e $clock_log && $cond_1) {
                $p_stage{'clock'}++;
                if (-e $route_log && $cond_2) {
                    $p_stage{'route'}++;
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

foreach my $stage_name ('place', 'clock', 'route') {
    if ($p_stage{$stage_name} >= 1) {
        push @pnr_stages, $stage_name;
    }
}

print "@pnr_stages\n";

if (!$print_timing && !$print_density && !$print_congestion && !$print_violation && !$print_vt) {
    $print_timing = $print_density = $print_congestion = $print_violation = $print_vt = 1;
}

if (defined $csv_file) {
    open($fh, '>', $csv_file) or die "Cannot open file '$csv_file' for writing: $!\n";
}

foreach my $pnr (@pnr_stages) {
    my @rpt_dirs; my @timing_rpt_dirs; my @setup_qor_rpts; my @hold_qor_rpts; my @vt_rpts; my @drc_rpts;
	my @gzipped_files;  # To store files that were gzipped for later unzipping
	
    foreach my $invs (@invs_dir) {
	$invs =~ s/\/$//;
        my $rpt_dir_tmp = "${invs}/$define_stage{$pnr}/rpts";
        if (-d $rpt_dir_tmp) {
            push @rpt_dirs, $rpt_dir_tmp;

            my $timing_rpt_dir_tmp = `ls $rpt_dir_tmp/timing_0* -d 2>/dev/null | tail -1`; chomp $timing_rpt_dir_tmp;
            $timing_rpt_dir_tmp = $timing_rpt_dir_tmp ? $timing_rpt_dir_tmp : "-";
            push @timing_rpt_dirs, $timing_rpt_dir_tmp;

            if ($timing_rpt_dir_tmp ne "-") {			
				if (defined $invs_timing_summary) {
                    my $setup_qor_rpt_tmp = `ls ${rpt_dir_tmp}/invs_timing_summary* 2>/dev/null | tail -1`; 
                    chomp $setup_qor_rpt_tmp;
                    if ($setup_qor_rpt_tmp && $setup_qor_rpt_tmp !~ /\.gz$/) {
                        system("gzip $setup_qor_rpt_tmp");
                        $setup_qor_rpt_tmp .= ".gz";
                        push @gzipped_files, $setup_qor_rpt_tmp;  # Track the gzipped file
                    }
                    $setup_qor_rpt_tmp = $setup_qor_rpt_tmp ? $setup_qor_rpt_tmp : "-";
                    push @setup_qor_rpts, $setup_qor_rpt_tmp;

                    if ($pnr ne "place") {
                        my $hold_qor_rpt_tmp = `ls ${rpt_dir_tmp}/invs_timing_summary* 2>/dev/null | tail -1`; 
                        chomp $hold_qor_rpt_tmp;
                        if ($hold_qor_rpt_tmp && $hold_qor_rpt_tmp !~ /\.gz$/) {
                            system("gzip $hold_qor_rpt_tmp");
                       	    print "gzipesd $hold_qor_rpt_tmp\n";
							$hold_qor_rpt_tmp .= ".gz";
                            push @gzipped_files, $hold_qor_rpt_tmp;  # Track the gzipped file
                        }
                        $hold_qor_rpt_tmp = $hold_qor_rpt_tmp ? $hold_qor_rpt_tmp : "-";
                        push @hold_qor_rpts, $hold_qor_rpt_tmp;
                    }
                } else {
                    my $setup_qor_rpt_tmp = `ls ${timing_rpt_dir_tmp}/${design}*.summary.gz 2>/dev/null | grep -v "hold\.summary" | tail -1`; 
                    chomp $setup_qor_rpt_tmp;
                    $setup_qor_rpt_tmp = $setup_qor_rpt_tmp ? $setup_qor_rpt_tmp : "-";
                    push @setup_qor_rpts, $setup_qor_rpt_tmp;

                    if ($pnr ne "place") {
                        my $hold_qor_rpt_tmp = `ls ${timing_rpt_dir_tmp}/${design}*hold.summary.gz 2>/dev/null`; 
                        chomp $hold_qor_rpt_tmp;
                        $hold_qor_rpt_tmp = $hold_qor_rpt_tmp ? $hold_qor_rpt_tmp : "-";
                        push @hold_qor_rpts, $hold_qor_rpt_tmp;
                    }
                }

            my $vt_rpt_tmp = `ls ${rpt_dir_tmp}/av_gate_count.rpt.gz 2>/dev/null`; chomp $vt_rpt_tmp;
            $vt_rpt_tmp = $vt_rpt_tmp ? $vt_rpt_tmp : "-";
            push @vt_rpts, $vt_rpt_tmp;

            if ($pnr eq "route") {
                my $drc_rpt_tmp = `ls ${rpt_dir_tmp}/invs_drc_summary.gz 2>/dev/null`; chomp $drc_rpt_tmp;
                $drc_rpt_tmp = $drc_rpt_tmp ? $drc_rpt_tmp : "-";
                push @drc_rpts, $drc_rpt_tmp;
            }

            }
        } else {
            $rpt_dir_tmp = "-";
            push @rpt_dirs, $rpt_dir_tmp;
        }
    }
    my $all_dash = 1;
    foreach my $dir (@rpt_dirs) {
        if ($dir ne "-") {
            $all_dash = 0;
            last;
        }
    }
    if ($all_dash) {
        next;
    }
    format wholeHeader =

+-----------------------------------------------------------------------------------------------------------------------------------------------------+
|                                       >>>>>>>>>>>>>>>>>>>>>    Stage @<<<<<<< <<<<<<<<<<<<<<<<<<<<<                                                 |
$pnr
+-----------------------------------------------------------------------------------------------------------------------------------------------------+
.

    $~ = wholeHeader;
    write;

    get_timing_table("Setup mode", @setup_qor_rpts) if $print_timing;
    
    if ($pnr ne "place" && $print_timing) {
        get_timing_table("Hold mode", @hold_qor_rpts);
    }

    get_density_table(@setup_qor_rpts) if $print_density;
    
    if ($pnr ne "route" && $print_congestion) {
        get_congestion_table(@setup_qor_rpts);
    } elsif ($pnr eq "route" && $print_violation) {
        get_violation_table(@drc_rpts);
    }

    get_vt_table(@vt_rpts) if $print_vt;

    if (defined $csv_file) {
	print $fh ",Stage $define_stage{$pnr},,\n";
	get_timing_csv_table("Setup mode", @setup_qor_rpts) if $print_timing;
	print $fh "\n";
	if ($pnr ne "place" && $print_timing) {
	    get_timing_csv_table("Hold mode", @hold_qor_rpts);
	    print $fh "\n";
	}
	get_density_csv_table(@setup_qor_rpts) if $print_density;
	print $fh "\n";
	if ($pnr ne "route" && $print_congestion) {
	    get_congestion_csv_table(@setup_qor_rpts);
	    print $fh "\n";
	} elsif ($pnr eq "route" && $print_violation) {
	    get_violation_csv_table(@drc_rpts);
	    print $fh "\n";
	}
	get_vt_csv_table(@vt_rpts) if $print_vt;
	print $fh "\n";
    }
	
	if (defined $invs_timing_summary) {
		foreach my $gzipped_file (@gzipped_files) {
			system("gunzip $gzipped_file");
		}
	}
}


if (defined $csv_file) {
    close $fh;
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

# ------------------------------------ subs to get timing table ----------------------------------------------
sub get_path_groups {
    my ($mode, $file_path) = @_;
    my @path_groups;
    if (-e $file_path) {
        my $output = `zcat $file_path | awk -F'|' -v mod='$mode' '/$mode/ { for (i=3; i<NF; i++) { print \$i } }'`;
        @path_groups = split /\n/, $output;
        @path_groups = map { s/^\s+|\s+$//gr } @path_groups;
        chomp(@path_groups);  # Remove trailing newlines
    } else {
        @path_groups = ();
    }
    return @path_groups;
}
sub get_combined_path_groups {
    my ($mode, @file_paths) = @_;
    my %unique_elements;
    foreach my $file_path (@file_paths) {
        my @path_groups = get_path_groups($mode, $file_path);
        foreach my $element (@path_groups) {
            $unique_elements{$element} = 1;
        }
    }
    my @sorted_unique_elements = sort keys %unique_elements;
    return @sorted_unique_elements;
}
sub get_wns_tns_vp {
    my ($mode, $path_group, $field, $file) = @_;
    if (-e $file) {
        my $value = `zcat $file | awk -F'|' -v mod='$mode' -v path='$path_group' -v value="$field" '
            BEGIN {col=-1; trace_row=""; out="-"}
            \$0 ~ mod {trace_row=NR}
            trace_row && \$0 ~ path {
                found=0
                for (i=1; i<=NF; i++) {if (\$i ~ path) {col=i; found=1; break}}
            }
            trace_row && \$0 ~ value {out=(found ? \$col : "-"); trace_row=0}
            END {print out}
        '`;
        $value =~ s/^\s+|\s+$//g;
        return $value;
    } else {
        return "-";
    }
}
sub get_timing_table {
    my ($mode, @file_paths) = @_;
    my @combined_path_groups = get_combined_path_groups($mode, @file_paths);
    my %path_groups_with_data;
    foreach my $one_file (@file_paths) {
        foreach my $one_path_group (@combined_path_groups) {
            foreach my $one_wtv ('WNS', 'TNS', 'Violating') {
                my $value = get_wns_tns_vp($mode, $one_path_group, $one_wtv, $one_file);
                $path_groups_with_data{$one_path_group}{$one_file}{$one_wtv} = $value;
            }
        }
    }

    my @dir_names;
    my $divider = "+" . "-" x $divider_width . "+";
    my $mode_header = sprintf("|  %-*s|", $field_col_width, "$mode (wns/tns/vp)");
    foreach my $file (@file_paths) {
	if (-e $file) {
	    my @dirs = split(/\//, $file);
            $divider .= "-" x ($col_width+2) . "+";
    	    my $dir_name;
	    if ($file =~ /invs_timing_summary/) {
		$dir_name = $dirs[-4];
	    } else {
		$dir_name = $dirs[-5];
	    }
            if (length($dir_name) > $col_width ) {
               my $dir = substr($dir_name, 0, $col_width - 1) . "...";
               $mode_header .= sprintf("%-*s|", $col_width, $dir);
            } else {
                $mode_header .= sprintf("  %-*s|", $col_width, $dir_name);
            }
	} else {
	  $divider .= "-" x ($col_width+2) . "+";
	  $mode_header .= sprintf("  %-*s|", $col_width, "\-");
	} 
    }

    
   
    print "\n$divider\n$mode_header\n$divider\n";

    foreach my $one_path_group (@combined_path_groups) {
        my @wtn;
        foreach my $file (@file_paths) {
            my $wtn_str = sprintf("%s/%s/%s", 
                ($path_groups_with_data{$one_path_group}{$file}{'WNS'} // '-'), 
                ($path_groups_with_data{$one_path_group}{$file}{'TNS'} // '-'), 
                ($path_groups_with_data{$one_path_group}{$file}{'Violating'} // '-')
            );
            if (length($wtn_str) > $col_width) {
                $wtn_str = substr($wtn_str, 0, $col_width) . "..";
                push @wtn, sprintf("%-*s|", $col_width, $wtn_str);
            } else {
                push @wtn, sprintf("  %-*s|", $col_width, $wtn_str);
            }
        }
        if (length($one_path_group) > $field_col_width) {
            $one_path_group = substr($one_path_group, 0, ($field_col_width -4)) . "...";
        }
        my $body_row = sprintf("|  %-*s|%s", $field_col_width, $one_path_group, join("", @wtn));
        print "$body_row\n";
    }
    print "$divider\n";
}
# ------------------------------------------------------------------------------------------------------------

# ------------------------------------ subs to get density table ---------------------------------------------
sub get_density {
    my ($rpt) = @_;
    if (-e $rpt) {
		if ($rpt =~ /invs_timing_summary/) {
			my $density = `zcat $rpt | awk '/Density/ {print \$NF}'`;
			chomp $density;
			return $density;
		} else {
			my @density = `zcat $rpt | egrep -e "Density:" | awk '{for(i=1;i<=NF;i++){ if(\$i ~ "Density:"){print \$(i+1)} } }'`;
			chomp @density;
			return $density[0];
		}
    } else {
        return "-";
    }
}

sub get_density_table {
    my (@files) = @_;
    my $divider = "+" . "-" x $divider_width . "+";
    my $body = sprintf("|  %-*s|", $field_col_width, "Density (%)");
    foreach my $file (@files) {
        $divider .= "-" x ($col_width+2) . "+";
		if ($file =~ /invs_timing_summary/) {
			$body .= sprintf("  %-${col_width}s|", get_density($file));
		} else {
			$body .= sprintf("  %-${col_width}s|", get_density($file));
		}
        
    }
    print "$divider\n$body\n$divider\n";
}
# ------------------------------------------------------------------------------------------------------------

# ------------------------------------ subs to get congestion table ------------------------------------------
sub get_congestion {
    my ($rpt) = @_;
    if (-e $rpt) {
        my $congestion = `zcat $rpt | awk '/Routing Overflow.*H.*V/ {print \$0}' | awk '{print \$(NF-4)" "\$(NF-3)"  " \$(NF-1)" "\$NF}'`;
        chomp $congestion;
        return $congestion;
    } else {
        return "-";
    }
}
sub get_congestion_table {
    my (@files) = @_;
    my $divider = "+" . "-" x $divider_width . "+";
    my $body = sprintf("|  %-*s|", $field_col_width, "Routing Overflow");
    foreach my $file (@files) {
        $divider .= "-" x ($col_width+2) . "+";
        $body .= sprintf("  %-${col_width}s|", get_congestion($file));
    }
    print "$body\n$divider\n";
}
# ------------------------------------------------------------------------------------------------------------

# ------------------------------------ subs to get violation table -------------------------------------------
sub get_violation {
    my ($rpt) = @_;
    my ($shorts, $total_drc) = ("no vio", "no vio");
    if (-e $rpt) {
        $shorts = `zegrep "Metal Short" $rpt | awk '{print \$4}'`;
        $total_drc = `zegrep "Total" $rpt | awk '{print \$3}'`;
        
        chomp $shorts;
        chomp $total_drc;
        
        $shorts = $shorts eq '' ? "No Violation" : $shorts;
        $total_drc = $total_drc eq '' ? "No Violation" : $total_drc;
    } else {
        $shorts = "-";
        $total_drc = "-";
    }
    return $shorts, $total_drc;
}

sub get_violation_table {
    my (@files) = @_;
    my $divider = "+" . "-" x $divider_width . "+";
    my $short_body = sprintf("|  %-*s|", $field_col_width, "Shorts");
    my $total_body = sprintf("|  %-*s|", $field_col_width, "DRCs");
    foreach my $file (@files) {
        $divider .= "-" x ($col_width+2) . "+";
        my ($short_tmp, $total_tmp) = get_violation($file);
        $short_body .= sprintf("  %-${col_width}s|", $short_tmp);
        $total_body .= sprintf("  %-${col_width}s|", $total_tmp);
    }
    print "$short_body\n$divider\n$total_body\n$divider\n"
}
# ------------------------------------------------------------------------------------------------------------

# ------------------------------------ subs to get vt table --------------------------------------------------
sub get_vt_per {
    my $rpt = $_[0];
    my @vt_types = ('SVT', 'SVTLL', 'LVT', 'LVTLL', 'ULVT', 'ULVTLL', 'ELVT');
    my @vt_values;

    if (-e $rpt) {
        foreach my $vt (@vt_types) {
            my $value = `zcat $rpt | sed -e '1,/${design}:/ d' | grep '[[:blank:]]$vt ' | awk '{print \$(NF-1)}'`;
            chomp $value;
            push @vt_values, $value || "-";
        }
        return @vt_values;
    } else {
        return ("-", "-", "-", "-", "-", "-", "-");
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
    my @all_vt = ('SVT', 'SVTLL', 'LVT', 'LVTLL', 'ULVT', 'ULVTLL', 'ELVT');

    for (my $i = 0; $i < @all_vt; $i++) {
        my $row = sprintf("|  %-*s|", $field_col_width, $all_vt[$i]);
        foreach my $vt_ref (@vt_values) {
            $row .= sprintf("  %-${col_width}s|", $vt_ref->[$i]);
        }
        print "$row\n";
    }
    print "$divider\n";
}
# -------------------------------------------------------------------------------------------------------------------

# --------------------------------------- all subs for csv file -----------------------------------------------------
sub get_timing_csv_table {
    my ($mode, @file_paths) = @_;
    my @combined_path_groups = get_combined_path_groups($mode, @file_paths);
    my %path_groups_with_data;
    foreach my $one_file (@file_paths) {
        foreach my $one_path_group (@combined_path_groups) {
            foreach my $one_wtv ('WNS', 'TNS', 'Violating') {
                my $value = get_wns_tns_vp($mode, $one_path_group, $one_wtv, $one_file);
                $path_groups_with_data{$one_path_group}{$one_file}{$one_wtv} = $value;
            }
        }
    }

    my @dir_names;
	
    my @mode_header;
    push @mode_header, "$mode (WNS/TNS/Violating paths)";
    foreach my $file (@file_paths) {
	if (-e $file) {
            my @dirs = split(/\//, $file);
	    my $header_tmp;
	    if ($file =~ /invs_timing_summary/) {
		$header_tmp = $dirs[-4];
	    } else {
		$header_tmp = $dirs[-5];
	    }
            push @mode_header, $header_tmp;
		} else {
			push @mode_header, "\-";
		} 
    }
	print $fh join(",", @mode_header) . "\n";

    foreach my $one_path_group (@combined_path_groups) {
        my @wtn;
        foreach my $file (@file_paths) {
			my $wtn_str = sprintf("%s/%s/%s", 
                ($path_groups_with_data{$one_path_group}{$file}{'WNS'} // '-'), 
                ($path_groups_with_data{$one_path_group}{$file}{'TNS'} // '-'), 
                ($path_groups_with_data{$one_path_group}{$file}{'Violating'} // '-')
            );
			push @wtn, $wtn_str;	
        }
		print $fh join(",", $one_path_group, @wtn) . "\n";
    }
}

sub get_density_csv_table {
    my (@files) = @_;
	my @data;
	push @data, "Density (%)";
	
    foreach my $file (@files) {
        push @data, get_density($file);
    }
    print $fh join(",", @data) . "\n";
}

sub get_congestion_csv_table {
    my (@files) = @_;
    my @data;
    push @data, "Routing Overflow";
    foreach my $file (@files) {
        push @data, get_congestion($file);
    }
    print $fh join(",", @data) . "\n";
}

sub get_violation_csv_table {
    my (@files) = @_;
    my @shorts_data = ("Shorts");
    my @drcs_data = ("DRCs");
    
    foreach my $file (@files) {
        my ($short_tmp, $total_tmp) = get_violation($file);
        push @shorts_data, $short_tmp;
        push @drcs_data, $total_tmp;
    }
    print $fh join(",", @shorts_data) . "\n";
    print $fh join(",", @drcs_data) . "\n";
}

sub get_vt_csv_table {
    my (@files) = @_;
    my @vt_values;
    my @dirs;

    my @header = ("VT Table (%)");

    foreach my $file (@files) {
        push @vt_values, [get_vt_per($file)];
        
        # Extract the directory name or use '-' if file doesn't exist
        my @dir_split = split(/\//, $file);
        my $dir = (-e $file) ? $dir_split[-4] : "-";
        push @header, $dir;
    }

    # Write the header as a comma-separated line
    print $fh join(",", @header) . "\n";

    my @all_vt = ('SVT', 'SVTLL', 'LVT', 'LVTLL', 'ULVT', 'ULVTLL', 'ELVT');

    # Write each row of the VT table
    for (my $i = 0; $i < @all_vt; $i++) {
        my @row = ($all_vt[$i]);
        foreach my $vt_ref (@vt_values) {
            push @row, $vt_ref->[$i];
        }
        # Write the row as a comma-separated line
        print $fh join(",", @row) . "\n";
    }
}  
# ------------------------------------------------------------------------------------------------------------
