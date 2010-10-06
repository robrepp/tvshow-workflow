#!/usr/bin/perl -w
use strict;
use POSIX qw/strftime/;

# get_show function authored by tvrage.com
# available at http://tvrage.com/info/quickinfo.html
use LWP::Simple;
sub get_show {
my ($show) = $_[0];
my ($exact ) = $_[1];
my ($episode) = $_[2];
my @ret = "";
if ( $show ne "" ){
	my $site = get "http://services.tvrage.com/tools/quickinfo.php?show=".$show."&ep=".$episode."&exact=".$exact;
	foreach my $line (split("\n",$site) ){
		my ($sec,$val) = split('\@',$line,2);
		if ($sec eq "Show Name" ){$ret[0] = $val;}
		elsif ( $sec eq "Show URL" ){$ret[1] = $val;}
		elsif ( $sec eq "Premiered" ){$ret[2] = $val;}
		elsif ($sec eq "Country" ){$ret[7] = $val;}
		elsif ( $sec eq "Status" ){$ret[8] = $val;}
		elsif ( $sec eq "Classification" ){$ret[9] = $val;}
		elsif ( $sec eq "Genres" ){$ret[10] = $val;}
		elsif ( $sec eq "Network" ){$ret[11] = $val;}
		elsif ( $sec eq "Airtime" ){$ret[12] = $val;}
		elsif ( $sec eq "Latest Episode" ){my($ep,$title,$airdate) = split('\^',$val);$ret[3] = $ep.", \"".$title."\" aired on ".$airdate;}
		elsif ( $sec eq "Episode Info" ){my($ep,$title,$airdate) = split('\^',$val);$ret[5] = $title;$ret[4] = $airdate;}
		elsif ( $sec eq "Episode URL" ){$ret[6] = $val;}
		}
	if ( $ret[0] ){return @ret;}
	else{return 0;}
	}
return 0;
}

# load config file and set variables
open(CONFIG,"tvshow-workflow.config") or die $_;
my %config = ();
while (<CONFIG>) {
    chomp;
    next if /^\s*\#/;
    next unless /=/;
    my ($key, $variable) = split(/\s*=\s*/,$_,2);
    $variable =~ s/(\$(\w+))/$config{$2}/g;
    $config{$key} = $variable;
}

my $AP_bin=$config{'AtomicParsleyLocation'};
my $HB_CLI_bin=$config{'HandBrakeCLILocation'};
my $iTunes_auto_import_dir=$config{'iTunesAutoImportLocation'};

# file extensions to scan for
my $include="\'.avi|.mkv\'";

# create staging directories if they don't exist
unless (-d "./Staging") {
	mkdir "./Staging";
}

unless (-d "./Staging/Tagged") {
	mkdir "./Staging/Tagged";
}

unless (-d "./Staging/Originals") {
	mkdir "./Staging/Originals";
}

unless (-d "./Staging/Imported") {
	mkdir "./Staging/Imported";
}

unless (-d "./Staging/Encoding") {
	mkdir "./Staging/Encoding";
}

# list video files and assign that list to the videolist array
my @videolist = `ls -1 | grep -Ei $include`;

# moving all files to originals folder
foreach my $videofile (@videolist){
	# eat the return character at the end of the file name
	chomp $videofile;
	
	# move original file to Originals folder
	`mv "$videofile" ./Staging/Originals/"$videofile"`;
}

# main loop
foreach my $videofile (@videolist){
	# retrieve show name and replace periods with spaces
	my $newShowName = $videofile;
	$newShowName =~ s/(^.*)(\.s\d+e\d+.*)/$1/i;
	$newShowName =~ s/\./ /g;
	
	# retrieve season and episode string
	my $seasonEpisode = $videofile;
	$seasonEpisode =~ s/(^.*\.)(s\d+e\d+)(.*)/$2/i;
	
	# check to make sure both newShowName and seasonEpisode strings exist
	# if either string is missing report an error, otherwise proceed
	if (($newShowName eq $videofile) || ($seasonEpisode eq $videofile)) {
		print "\n##########\n";
		print "ERROR: Show name and/or season and episode numbers were not found in the video file name.\n";
		print "ERROR: Video file name: ";
		print $videofile;
		print "\n";
	} 
	else {
		# retrieve season and episode numbers
		my $newSeason = $seasonEpisode;
		my $newEpisode = $seasonEpisode;
		$newSeason =~ s/s(\d+)e(\d+)/$1/i;
		$newEpisode=~ s/s(\d+)e(\d+)/$2/i;
		
		# establish show_info array with information pulled from tvrage
		my @show_info = &get_show($newShowName,"1",$newSeason."x".$newEpisode);
		
		# build new file name
		my $newFileName = $newShowName." - S".$newSeason."E".$newEpisode.".m4v";
		
		# print show information
		print "\n##########\n";
		print "Show name: ";
		print $newShowName;
		print "\nEpisode title: ";
		print $show_info[5];
		print "\nNew File Name: ";
		print $newFileName;
		print "\n";
		
		# encode file with HandBrakeCLI
		print "\nEncoding file... (Start time: ". POSIX::strftime('%H:%M:%S', localtime).")";
		my $HBrun = `$HB_CLI_bin -i "./Staging/Originals/$videofile" -o "./Staging/Encoding/$newFileName" --preset="AppleTV" > /dev/null 2>&1`;
		print "\nEncoding complete. (End time: ". POSIX::strftime('%H:%M:%S', localtime).")\n##########\n";
		
		# use AtomicParsley to write the data to the file
		my $APrun = `"$AP_bin" "./Staging/Encoding/$newFileName" --TVShowName "$show_info[0]" --artist "$show_info[0]" --TVEpisode "$newEpisode" --title "$show_info[5]" --TVEpisodeNum "$newEpisode" --tracknum "$newEpisode" --TVSeasonNum "$newSeason" --album "Season $newSeason" --TVNetwork "$show_info[11]" --genre "$show_info[10]" --stik "TV Show" -o "./Staging/Tagged/$newFileName"`;
		
		# establish final path to tagged file
		my $finalPath = `pwd`;
		chomp $finalPath;
		$finalPath .= "/Staging/Tagged/$newFileName";
		
		# check if file exists before proceeding with import, move, and delete
		if (-e $finalPath) {
			# copy file to Auto-import iTunes directory
			`cp ./Staging/Tagged/"$newFileName" "$iTunes_auto_import_dir"`;
			
			# move new file to Imported folder
			`mv ./Staging/Tagged/"$newFileName" ./Staging/Imported/"$newFileName"`;
			
			# delete file in Encoding directory
			unlink("./Staging/Encoding/$newFileName");
		}
		
		else {
			print "ERROR: File not found for import into iTunes.\n";
			print "ERROR: Path to video file: ";
			print $finalPath;
			print "\n";
		}
	}
}